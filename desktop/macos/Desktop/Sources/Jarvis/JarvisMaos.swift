import AppKit
import Foundation

/// Mãos no Mac para o `mexer_no_mac` do Jarvis. O pedido é o JSON que o Claude monta no Fly; aceita os formatos
/// abaixo (chaves em português ou inglês) e devolve "não sei fazer isso ainda" com a lista, para ele tentar de novo.
enum JarvisMaos {
  enum Acao: Equatable {
    case abrirApp(String)
    case abrirURL(URL)
    case digitar(String)
    /// Pede ao 1Password do Mac (⌘\, autofill da extensão) que preencha o login da página da frente. A senha não
    /// passa pelo Jarvis, pelo Fly nem pela IA: quem preenche é o próprio 1Password.
    case preencherLogin
    case hands([String])  // verbos do `Atticus --hands`: see, click, type, press, scroll, menu, wait...
    case desconhecida
  }

  static let formatos =
    "Formatos aceitos: {\"acao\":\"abrir_app\",\"app\":\"Calculadora\"}, {\"acao\":\"abrir_url\",\"url\":\"https://...\"}, "
    + "{\"acao\":\"digitar\",\"texto\":\"...\"}, {\"acao\":\"preencher_login\"} (1Password preenche o login da página) ou {\"args\":[\"click\",\"Enviar\"]} (verbos do Atticus --hands: "
    + "see, click, type, press, scroll, menu, wait)."

  // MARK: - Leitura (puro, testado)

  static func ler(_ pedido: [String: Any]) -> Acao {
    func texto(_ chaves: String...) -> String? {
      for c in chaves {
        if let v = pedido[c] as? String, !v.trimmingCharacters(in: .whitespaces).isEmpty {
          return v.trimmingCharacters(in: .whitespaces)
        }
      }
      return nil
    }
    if let args = pedido["args"] as? [String], !args.isEmpty { return .hands(args) }
    let acao = (texto("acao", "ação", "action", "tipo", "verbo") ?? "")
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
      .replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "-", with: "_")
    let app = texto("app", "aplicativo", "nome", "alvo", "target", "name")
    let url = texto("url", "link", "endereco").flatMap(URL.init(string:))
    let digitado = texto("texto", "text", "conteudo")

    switch acao {
    case "abrir_app", "open_app", "launch", "abrir_aplicativo":
      return app.map(Acao.abrirApp) ?? .desconhecida
    case "abrir_url", "open_url", "navegar", "abrir_link", "abrir_site":
      return url.map(Acao.abrirURL) ?? .desconhecida
    case "abrir", "open":
      if let url, url.scheme != nil { return .abrirURL(url) }
      return app.map(Acao.abrirApp) ?? .desconhecida
    case "digitar", "type", "escrever", "type_text":
      return digitado.map(Acao.digitar) ?? .desconhecida
    case "preencher_login", "login", "autofill", "fazer_login", "logar":
      return .preencherLogin
    case "":
      if let url, url.scheme != nil { return .abrirURL(url) }
      return app.map(Acao.abrirApp) ?? .desconhecida
    default:
      return .desconhecida
    }
  }

  /// "Calculadora" acha o Calculator.app pelo nome que o Finder mostra; caixa e acento não importam.
  static func mesmoNome(_ a: String, _ b: String) -> Bool {
    let f = { (s: String) in
      s.replacingOccurrences(of: ".app", with: "")
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        .trimmingCharacters(in: .whitespaces)
    }
    return f(a) == f(b)
  }

  // MARK: - Execução

  @MainActor static func executar(_ pedido: [String: Any]) async -> [String: Any] {
    if pedido["omi"] != nil { return await JarvisOmi.consultar(pedido) }
    if pedido["tela"] != nil { return printDaTela() }
    if pedido["sessoes"] != nil { return await JarvisSessoes.consultar(pedido) }
    let acao = ler(pedido)
    log("Jarvis: mexer_no_mac \(acao)")
    switch acao {
    case .abrirApp(let nome):
      guard let url = acharApp(nome) else { return falha("Não achei o app \(nome) neste Mac.") }
      do {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
        return ok("Abri \(FileManager.default.displayName(atPath: url.path)).")
      } catch {
        return falha("Não consegui abrir \(nome): \(error.localizedDescription)")
      }
    case .abrirURL(let url):
      // file:// abriria qualquer executável do disco; isso fica para as mãos do Atticus
      guard let scheme = url.scheme?.lowercased(), scheme != "file" else {
        return falha("Só abro endereço web ou de app, não arquivo.")
      }
      return NSWorkspace.shared.open(url) ? ok("Abri \(url.absoluteString).") : falha("Não consegui abrir \(url).")
    case .digitar(let texto):
      guard AXIsProcessTrusted() else {
        return falha(
          "O Omi Fork não tem permissão de Acessibilidade para digitar. O Gabriel precisa liberar nos Ajustes.")
      }
      digitar(texto)
      return ok("Digitei \(texto.count) caracteres no app da frente.")
    case .preencherLogin:
      guard AXIsProcessTrusted() else {
        return falha(
          "O Omi Fork não tem permissão de Acessibilidade para acionar o 1Password. O Gabriel precisa liberar nos Ajustes."
        )
      }
      guard let navegador = trazerNavegador() else { return falha("Não achei um navegador aberto.") }
      // espera a página carregar (a URL costuma ter acabado de abrir)
      try? await Task.sleep(nanoseconds: 2_500_000_000)
      atalhoUmPassword()
      return ok(
        "Pedi ao 1Password para preencher o login no \(navegador); se ele pedir Touch ID, confirme. "
          + "Falta clicar em Entrar, se a página não entrar sozinha.")
    case .hands(let args):
      return await hands(args)
    case .desconhecida:
      return falha("Não sei fazer isso ainda. " + formatos)
    }
  }

  /// Maior lado do print mandado ao cérebro: o Claude reduz imagem maior que ~1.568 px, então mandar mais é só peso.
  nonisolated static let ladoPrint = 1568

  /// Print da tela sob o mouse, em JPEG reduzido, para o cérebro ler o que está escrito (o `see` do Atticus só vê a
  /// árvore de acessibilidade, e app como o Claude não expõe o texto da conversa nela).
  static func printDaTela() -> [String: Any] {
    guard let tela = ScreenCaptureManager.captureScreenImage() else {
      return falha("Não consegui tirar o print: o Omi Fork precisa da permissão de Gravação de Tela.")
    }
    let escala = min(1, Double(ladoPrint) / Double(max(tela.width, tela.height)))
    let largura = Int(Double(tela.width) * escala)
    let altura = Int(Double(tela.height) * escala)
    guard
      let ctx = CGContext(
        data: nil, width: largura, height: altura, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { return falha("Não consegui reduzir o print.") }
    ctx.interpolationQuality = .high
    ctx.draw(tela, in: CGRect(x: 0, y: 0, width: largura, height: altura))
    guard let menor = ctx.makeImage(), let jpeg = ScreenCaptureManager.jpegData(from: menor, quality: 0.75) else {
      return falha("Não consegui gerar o JPEG do print.")
    }
    log("Jarvis: print da tela \(largura)x\(altura), \(jpeg.count / 1024) KB")
    return [
      "ok": true, "mensagem": "Print da tela \(largura)x\(altura).", "imagem_jpeg_base64": jpeg.base64EncodedString(),
    ]
  }

  private static func ok(_ m: String) -> [String: Any] { ["ok": true, "mensagem": m] }
  private static func falha(_ m: String) -> [String: Any] { ["ok": false, "mensagem": m] }

  @MainActor private static func acharApp(_ nome: String) -> URL? {
    if nome.contains("."), let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: nome) { return url }
    let fm = FileManager.default
    let pastas = [
      "/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
      NSHomeDirectory() + "/Applications",
    ]
    for pasta in pastas {
      for item in (try? fm.contentsOfDirectory(atPath: pasta)) ?? [] where item.hasSuffix(".app") {
        let caminho = pasta + "/" + item
        if mesmoNome(item, nome) || mesmoNome(fm.displayName(atPath: caminho), nome) {
          return URL(fileURLWithPath: caminho)
        }
      }
    }
    return nil
  }

  static let navegadores = [
    "com.google.Chrome", "com.apple.Safari", "company.thebrowser.Browser", "com.brave.Browser",
    "com.microsoft.edgemac", "org.mozilla.firefox",
  ]

  /// O navegador da frente, ou o último usado (o que acabou de abrir a URL), vai para o foco.
  @MainActor private static func trazerNavegador() -> String? {
    let ws = NSWorkspace.shared
    if let frente = ws.frontmostApplication, navegadores.contains(frente.bundleIdentifier ?? "") {
      return frente.localizedName
    }
    // runningApplications não vem em ordem de uso; o navegador padrão é o que abriu a URL do abrir_url
    let padrao = ws.urlForApplication(toOpen: URL(string: "https://example.com")!)
      .flatMap { Bundle(url: $0)?.bundleIdentifier }
    let abertos = ws.runningApplications.filter { navegadores.contains($0.bundleIdentifier ?? "") }
    guard let app = abertos.first(where: { $0.bundleIdentifier == padrao }) ?? abertos.first else { return nil }
    app.activate()
    usleep(400_000)
    return app.localizedName
  }

  /// ⌘\ é o atalho padrão de preenchimento da extensão do 1Password.
  private static func atalhoUmPassword() {
    let fonte = CGEventSource(stateID: .hidSystemState)
    let barraInvertida: CGKeyCode = 42  // kVK_ANSI_Backslash
    for desce in [true, false] {
      let e = CGEvent(keyboardEventSource: fonte, virtualKey: barraInvertida, keyDown: desce)
      e?.flags = .maskCommand
      e?.post(tap: .cghidEventTap)
    }
  }

  /// Digita no app da frente como se fosse o teclado, em pedaços (o CGEvent aceita até 20 caracteres por evento).
  private static func digitar(_ texto: String) {
    let fonte = CGEventSource(stateID: .hidSystemState)
    let unidades = Array(texto.utf16)
    var i = 0
    while i < unidades.count {
      let pedaco = Array(unidades[i..<min(i + 20, unidades.count)])
      for desce in [true, false] {
        let e = CGEvent(keyboardEventSource: fonte, virtualKey: 0, keyDown: desce)
        e?.keyboardSetUnicodeString(stringLength: pedaco.count, unicodeString: pedaco)
        e?.post(tap: .cghidEventTap)
      }
      i += 20
      usleep(8_000)
    }
  }

  /// O motor do Atticus vem embutido em Contents/Resources/atticus pelo `scripts/embutir-atticus.sh`.
  private static func hands(_ args: [String]) async -> [String: Any] {
    guard let bin = Bundle.main.resourceURL?.appendingPathComponent("atticus/Atticus"),
      FileManager.default.isExecutableFile(atPath: bin.path)
    else { return falha("O motor do Atticus não está embutido neste app.") }
    let (saida, codigo) = await rodar(bin, ["--hands"] + args)
    let texto = String(saida.suffix(2000))
    return codigo == 0
      ? ok(texto.isEmpty ? "Feito." : texto) : falha(texto.isEmpty ? "Atticus saiu com \(codigo)." : texto)
  }

  private static func rodar(_ bin: URL, _ args: [String]) async -> (String, Int32) {
    await withCheckedContinuation { c in
      let p = Process()
      p.executableURL = bin
      p.arguments = args
      let cano = Pipe()
      p.standardOutput = cano
      p.standardError = cano
      p.standardInput = FileHandle.nullDevice
      do {
        try p.run()
        // o Fly espera 60 s pela resposta
        DispatchQueue.global().asyncAfter(deadline: .now() + 45) { if p.isRunning { p.terminate() } }
        // lê antes de esperar: saída grande (o `see`) encheria o cano e travaria o processo
        DispatchQueue.global().async {
          let dados = cano.fileHandleForReading.readDataToEndOfFile()
          p.waitUntilExit()
          c.resume(
            returning: (
              String(decoding: dados, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
              p.terminationStatus
            ))
        }
      } catch {
        c.resume(returning: ("Não consegui rodar o Atticus: \(error.localizedDescription)", -1))
      }
    }
  }
}
