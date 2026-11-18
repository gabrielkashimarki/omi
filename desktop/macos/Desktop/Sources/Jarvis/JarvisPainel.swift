import AppKit
import WebKit

/// Fases do painel e quando ele some (puro, testado).
struct JarvisPainelEstado: Equatable {
  enum Fase: String { case pronto, ouvindo, pensando, confirmando, respondeu }
  static let sumirDepois: TimeInterval = 20

  private(set) var fase: Fase = .pronto
  private(set) var ultimaAtividade = Date()

  mutating func ir(_ f: Fase, agora: Date = Date()) {
    fase = f
    ultimaAtividade = agora
  }

  mutating func atividade(agora: Date = Date()) { ultimaAtividade = agora }

  /// Some 20 s depois da última atividade, mas nunca enquanto ouve, pensa ou espera a confirmação.
  func deveSumir(agora: Date = Date()) -> Bool {
    (fase == .pronto || fase == .respondeu) && agora.timeIntervalSince(ultimaAtividade) >= Self.sumirDepois
  }
}

/// Conversa contínua (puro, testado): depois da resposta o painel volta a ouvir por 8 s, sem o Hey Jarvis.
enum JarvisConversa {
  static let janela: TimeInterval = 8

  /// Abre só fora de reunião, com o painel solto aberto, sem o TTS tocando (o microfone ouviria a própria voz),
  /// depois de resposta ou pedido de confirmação, e se o Gabriel não encerrou a conversa.
  static func abreJanela(
    fase: JarvisPainelEstado.Fase, reuniao: Bool, painelAberto: Bool, falando: Bool, encerrada: Bool
  ) -> Bool {
    (fase == .respondeu || fase == .confirmando) && !reuniao && painelAberto && !falando && !encerrada
  }

  private static let sim: Set<String> = ["sim", "confirmo", "confirma", "pode"]
  private static let nao: Set<String> = ["nao", "recuso", "recusa", "cancela"]

  /// "Confirmo." vira true, "não, cancela" vira false; frase com outra coisa é pedido novo (nil).
  static func respostaFalada(_ texto: String) -> Bool? {
    let palavras = texto.folding(
      options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "pt_BR")
    )
    .split { !$0.isLetter }.map(String.init)
    guard !palavras.isEmpty, palavras.allSatisfy({ sim.contains($0) || nao.contains($0) }) else { return nil }
    return !palavras.contains(where: nao.contains)
  }
}

/// Painel do Jarvis: fora de reunião, um NSPanel próprio (as mesmas classes do copiloto) com o `jarvis-painel.js`;
/// na reunião, a aba Jarvis do `meeting.html`, com a mesma UI. Ouve pela legenda do Deepgram, pede ao `/jarvis`
/// e fala a resposta na voz do Gemini (`MeetingCopilotVoice`; sem chave do Gemini, só o texto).
@MainActor
final class JarvisPainel: NSObject, WKScriptMessageHandler {
  static let shared = JarvisPainel()

  private var panel: NSPanel?
  private var proprio: WKWebView?
  private weak var reuniao: WKWebView?
  private var pronto: Set<ObjectIdentifier> = []
  private var fila: [(String, Any)] = []  // chamadas antes da página montar
  private var estado = JarvisPainelEstado()
  private var relogio: Timer?
  private let legenda = JarvisLegenda()
  private var silencio: DispatchWorkItem?
  /// Id da confirmação em aberto: "confirmo" ou "recuso" falados respondem a ela.
  private var pendente: String?
  /// Escuta aberta sozinha depois da resposta: silêncio só para de ouvir, sem "Não ouvi nada".
  private var continuando = false
  /// O Gabriel tocou em Encerrar: nada reabre sozinho até o próximo pedido dele.
  private var encerrada = false

  var ouvindo: Bool { estado.fase == .ouvindo }
  var fase: JarvisPainelEstado.Fase { estado.fase }
  private var alvo: WKWebView? { reuniao ?? proprio }

  /// A página do painel, para a aba Jarvis do copiloto também.
  static var script: String {
    let base =
      Bundle.main.url(forResource: "Omi Computer_Omi Computer", withExtension: "bundle") ?? Bundle.main.resourceURL
    guard let url = base?.appendingPathComponent("jarvis-painel.js"),
      let js = try? String(contentsOf: url, encoding: .utf8)
    else {
      log("Jarvis: jarvis-painel.js não está no app")
      return ""
    }
    return js
  }

  override init() {
    super.init()
    legenda.aoOuvir = { [weak self] t in
      self?.chamar("legenda", t)
      // já falou: a guarda dos 8 s sai; se o Deepgram calar sem fechar a frase, 4 s depois vai o que foi dito
      self?.guardarSilencio(4)
    }
    legenda.aoTerminar = { [weak self] t in self?.ouviu(t) }
    legenda.aoFalhar = { [weak self] t in
      guard let self else { return }
      self.mudar(.pronto)
      self.chamar("erro", t)
      self.chamar("focar")
    }
  }

  // MARK: - Abrir e fechar

  func abrir(ouvindo: Bool) {
    if MeetingCopilot.shared.gravando {
      MeetingCopilot.shared.mostrarJarvis()
    } else if panel == nil {
      criar()
    } else {
      panel?.orderFrontRegardless()
    }
    estado.atividade()
    if ouvindo { ouvir() }
  }

  private func criar() {
    let tela = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
    let tamanho = NSSize(width: 360, height: 460)
    let frame = NSRect(
      x: tela.maxX - tamanho.width - 12, y: tela.maxY - tamanho.height - 12, width: tamanho.width,
      height: tamanho.height)
    let p = CopilotPanel(
      contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    p.level = .statusBar
    p.isOpaque = false
    p.backgroundColor = .clear
    p.hasShadow = true
    p.hidesOnDeactivate = false
    p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    p.sharingType = .none

    let config = WKWebViewConfiguration()
    config.userContentController.add(self, name: "jarvis")  // singleton: o ciclo não vaza
    config.userContentController.addUserScript(
      WKUserScript(
        source: Self.script + "\njarvis.mount(document.body, {sozinho: true});",
        injectionTime: .atDocumentEnd, forMainFrameOnly: true))
    let v = CopilotWebView(frame: NSRect(origin: .zero, size: frame.size), configuration: config)
    v.setValue(false, forKey: "drawsBackground")
    v.autoresizingMask = [.width, .height]
    let fundo = NSVisualEffectView(frame: v.frame)
    fundo.material = .hudWindow
    fundo.state = .active
    fundo.appearance = NSAppearance(named: .darkAqua)
    fundo.wantsLayer = true
    fundo.layer?.cornerRadius = 18
    fundo.layer?.masksToBounds = true
    fundo.autoresizingMask = [.width, .height]
    fundo.addSubview(v)
    p.contentView = fundo
    panel = p
    proprio = v
    v.loadHTMLString(
      "<!doctype html><html lang=\"pt-BR\"><head><meta charset=\"utf-8\"><style>:root{color-scheme:dark}"
        + "html,body{margin:0;height:100%;background:rgba(18,18,20,.55)}body{padding:14px 16px;box-sizing:border-box}"
        + "</style></head><body></body></html>", baseURL: nil)
    p.orderFrontRegardless()
    relogio?.invalidate()
    relogio = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
      MainActor.assumeIsolated {
        let s = JarvisPainel.shared
        if s.proprio != nil, s.estado.deveSumir() { s.fechar() }
      }
    }
  }

  func fechar() {
    continuando = false
    legenda.parar()
    relogio?.invalidate()
    relogio = nil
    if let proprio {
      pronto.remove(ObjectIdentifier(proprio))
      proprio.configuration.userContentController.removeScriptMessageHandler(forName: "jarvis")
    }
    panel?.orderOut(nil)
    panel = nil
    proprio = nil
    if estado.fase == .ouvindo { mudar(.pronto) }
  }

  /// O copiloto começou a ouvir: a aba Jarvis dele vira o painel, e o painel solto sai.
  func entrarNaReuniao(_ web: WKWebView) {
    fechar()
    reuniao = web
    if pronto.contains(ObjectIdentifier(web)) { paginaPronta() }
  }

  func sairDaReuniao() {
    if let reuniao { pronto.remove(ObjectIdentifier(reuniao)) }
    reuniao = nil
    legenda.parar()
  }

  // MARK: - Ouvir, pedir e confirmar

  func ouvir() {
    // o botão do microfone enquanto ouve encerra a fala e manda o que foi dito
    if estado.fase == .ouvindo, legenda.ouvindo {
      terminarFala()
      return
    }
    encerrada = false
    escutar(continuacao: false)
  }

  private func escutar(continuacao: Bool) {
    continuando = continuacao
    MeetingCopilotVoice.shared.stop()
    mudar(.ouvindo)
    chamar("legenda", continuacao ? "Pode continuar, estou ouvindo…" : "")
    chamar("erro", "")
    chamar("conversa", continuacao)
    legenda.comecar()
    guardarSilencio(JarvisConversa.janela)  // sem fala em 8 s, para de ouvir
  }

  /// Fim da fala ou da tela da resposta: a conversa segue sem o Hey Jarvis.
  private func continuar() {
    guard
      JarvisConversa.abreJanela(
        fase: estado.fase, reuniao: JarvisMenu.reuniaoAtiva || reuniao != nil, painelAberto: proprio != nil,
        falando: MeetingCopilotVoice.shared.falando, encerrada: encerrada)
    else { return }
    escutar(continuacao: true)
  }

  /// Botão Encerrar: para de ouvir e de falar; o painel some pela regra de sempre.
  private func encerrar() {
    encerrada = true
    continuando = false
    silencio?.cancel()
    legenda.parar()
    MeetingCopilotVoice.shared.stop()
    chamar("conversa", false)
    chamar("legenda", "")
    if estado.fase == .ouvindo { mudar(pendente == nil ? .respondeu : .confirmando) }
  }

  /// O que foi dito: com confirmação em aberto, "confirmo" ou "recuso" respondem a ela; o resto é pedido.
  private func ouviu(_ texto: String) {
    if let id = pendente, let sim = JarvisConversa.respostaFalada(texto) {
      chamar("legenda", "")
      chamar("pedido", texto)
      confirmar(id, sim: sim)
      return
    }
    pedir(texto)
  }

  /// Guarda contra silêncio sem fim de frase do Deepgram. Antes de qualquer fala é a espera inicial; depois, é
  /// rearmada a cada palavra, então fala longa nunca é cortada.
  private func guardarSilencio(_ segundos: TimeInterval) {
    silencio?.cancel()
    let item = DispatchWorkItem {
      MainActor.assumeIsolated {
        let s = JarvisPainel.shared
        guard s.estado.fase == .ouvindo else { return }
        s.terminarFala()
      }
    }
    silencio = item
    DispatchQueue.main.asyncAfter(deadline: .now() + segundos, execute: item)
  }

  /// "Não ouvi nada" só quando nem final nem parcial trouxeram texto.
  private func terminarFala() {
    silencio?.cancel()
    if legenda.terminar() { return }  // aoTerminar → ouviu
    legenda.parar()
    chamar("conversa", false)
    if continuando {
      // a janela da conversa fechou em silêncio: volta ao que era, e o painel some pela regra
      continuando = false
      chamar("legenda", "")
      mudar(pendente == nil ? .respondeu : .confirmando)
      return
    }
    mudar(.pronto)
    chamar("erro", "Não ouvi nada. Fale de novo ou digite.")
  }

  func pedir(_ texto: String) {
    let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty else { return }
    silencio?.cancel()
    legenda.parar()
    encerrada = false
    continuando = false
    pendente = nil  // pedido novo recusa a confirmação em aberto no servidor
    chamar("conversa", false)
    mudar(.pensando)
    chamar("pedido", t)
    Task {
      do {
        try await JarvisCliente.pedir(t) { e in await MainActor.run { JarvisPainel.shared.evento(e) } }
        if estado.fase == .pensando { mudar(.respondeu) }
      } catch JarvisCliente.Falha.semChave {
        falhou("Falta a chave do Jarvis neste Mac.")
      } catch {
        log("Jarvis: pedido falhou (\(type(of: error)))")
        falhou("Jarvis fora do ar. Tente de novo em instantes.")
      }
    }
  }

  private func falhou(_ texto: String) {
    mudar(.respondeu)
    chamar("erro", texto)
  }

  private func evento(_ e: JarvisCliente.Evento) {
    switch e {
    case .passo(let p):
      estado.atividade()
      chamar("passo", JarvisCliente.passoLegivel(p))
    case .confirmar(let id, let resumo, let fala):
      pendente = id
      mudar(.confirmando)
      chamar("confirmar", ["id": id, "resumo": resumo])
      MeetingCopilotVoice.shared.speak(fala) { JarvisPainel.shared.continuar() }
    case .fim(let fala, let detalhe):
      pendente = nil
      mudar(.respondeu)
      chamar("resposta", ["fala": fala, "detalhe": detalhe])
      MeetingCopilotVoice.shared.speak(fala) { JarvisPainel.shared.continuar() }
    }
  }

  private func confirmar(_ id: String, sim: Bool) {
    pendente = nil
    continuando = false
    silencio?.cancel()
    legenda.parar()
    chamar("conversa", false)
    mudar(.pensando)
    Task {
      do {
        try await JarvisCliente.confirmar(id, sim: sim)
      } catch {
        log("Jarvis: confirmação falhou (\(type(of: error)))")
        falhou("A confirmação não chegou ao Jarvis.")
      }
    }
  }

  private func carregarHistorico() {
    Task {
      guard let itens = try? await JarvisCliente.historico() else { return }
      let linhas: [[String: Any]] = itens.map { m in
        [
          "papel": m.papel, "texto": m.texto, "detalhe": m.detalhe,
          "quando": (m.quando?.timeIntervalSince1970 ?? 0) * 1000,
        ]
      }
      chamar("historico", linhas)
    }
  }

  private func mudar(_ f: JarvisPainelEstado.Fase) {
    estado.ir(f)
    chamar("fase", f.rawValue)
    NotificationCenter.default.post(name: .jarvisMudou, object: nil)
  }

  // MARK: - Página

  private func paginaPronta() {
    chamar("fase", estado.fase.rawValue)
    let pendentes = fila
    fila = []
    for (f, v) in pendentes { chamar(f, v) }
    carregarHistorico()
  }

  private func chamar(_ funcao: String, _ valor: Any = [String: Any]()) {
    guard let alvo else { return }
    guard pronto.contains(ObjectIdentifier(alvo)) else {
      fila.append((funcao, valor))
      return
    }
    guard let js = Self.chamadaJS(funcao, valor) else { return }
    alvo.evaluateJavaScript(js)
  }

  /// O JS da chamada, com o valor serializado em JSON (aspas, acentos e quebras de linha escapados; puro, testado).
  nonisolated static func chamadaJS(_ funcao: String, _ valor: Any) -> String? {
    let args: [Any] = [valor]
    guard JSONSerialization.isValidJSONObject(args), let dados = try? JSONSerialization.data(withJSONObject: args)
    else { return nil }
    return "window.jarvis?.\(funcao)(...\(String(decoding: dados, as: UTF8.self)))"
  }

  func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
    guard let web = message.webView, let b = message.body as? [String: Any], let acao = b["do"] as? String
    else { return }
    if acao == "pronto" {
      // a aba Jarvis do copiloto monta antes de o copiloto começar a ouvir
      pronto.insert(ObjectIdentifier(web))
      if web === alvo { paginaPronta() }
      return
    }
    guard web === alvo else { return }
    estado.atividade()
    switch acao {
    case "pedir": pedir(b["texto"] as? String ?? "")
    case "ouvir": ouvir()
    case "confirmar": confirmar(b["id"] as? String ?? "", sim: b["sim"] as? Bool ?? false)
    case "foco": panel?.makeKey()
    case "fechar": fechar()
    case "encerrar": encerrar()
    default: break  // "ativo": a atividade já contou
    }
  }
}

extension Notification.Name {
  /// Fase do Jarvis ou estado de reunião mudou: o ícone da barra de menus se redesenha.
  static let jarvisMudou = Notification.Name("jarvisMudou")
}
