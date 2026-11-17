//
//  AgentesNotch.swift — o painel flutuante dos agentes: o mascote, as sessões e o cartão de permissão.
//
//  Era uma ilha fixa no notch (portada do Coucou, MIT, © 2026 Louis Raillé, aviso em
//  THIRD_PARTY_COUCOU_LICENSE: `IslandWindowController.swift` e o cartão de `IslandViewContent.swift`).
//  Cobria o topo das janelas, então virou um painel solto como o do copiloto (`CopilotPanel`): recolhido numa
//  pílula no canto inferior direito, arrastável, lembra onde foi solto e abre ao passar o mouse ou num pedido.
//

import AppKit
import Combine
import OmiTheme
import SwiftUI

/// Onde e de que tamanho o painel fica (puro, testado). A âncora é o canto inferior direito: o painel cresce
/// para cima e para a esquerda, que é para onde há espaço quando ele mora no canto da tela.
enum AgentesPainelPosicao {
  static let chaveCanto = "agentes.painel.canto"
  static let chaveEscondido = "agentes.painel.escondido"
  static let margem: CGFloat = 16

  static func tamanho(expandido: Bool, sessoes: Int, comPedido: Bool) -> NSSize {
    if comPedido { return NSSize(width: 380, height: 52 + 128) }
    guard expandido else { return NSSize(width: 92, height: 38) }
    return NSSize(width: 300, height: 52 + CGFloat(min(max(sessoes, 1), 6)) * 30)
  }

  /// Canto padrão: inferior direito da área visível.
  static func cantoPadrao(_ tela: NSRect) -> NSPoint {
    NSPoint(x: tela.maxX - margem, y: tela.minY + margem)
  }

  /// O quadro com o canto inferior direito em `canto`, sem sair da tela.
  static func quadro(canto: NSPoint, tamanho: NSSize, tela: NSRect) -> NSRect {
    var x = canto.x - tamanho.width
    var y = canto.y
    x = min(max(x, tela.minX), tela.maxX - tamanho.width)
    y = min(max(y, tela.minY), tela.maxY - tamanho.height)
    return NSRect(x: x, y: y, width: tamanho.width, height: tamanho.height)
  }

  static func ler(_ d: UserDefaults = .standard) -> NSPoint? {
    guard let a = d.array(forKey: chaveCanto) as? [Double], a.count == 2 else { return nil }
    return NSPoint(x: a[0], y: a[1])
  }

  static func gravar(_ p: NSPoint, _ d: UserDefaults = .standard) {
    d.set([Double(p.x), Double(p.y)], forKey: chaveCanto)
  }
}

@MainActor
final class AgentesNotch: ObservableObject {
  static let shared = AgentesNotch()

  @Published var expandido = false {
    didSet { if expandido != oldValue, let central { atualizar(central) } }
  }
  /// Escondido pelo botão do painel; volta pelo menu da barra. Pedido de permissão aparece mesmo assim, porque
  /// a sessão do Claude Code fica parada esperando.
  var escondido: Bool {
    get { UserDefaults.standard.bool(forKey: AgentesPainelPosicao.chaveEscondido) }
    set {
      UserDefaults.standard.set(newValue, forKey: AgentesPainelPosicao.chaveEscondido)
      if let central { atualizar(central) }
    }
  }

  private var painel: NSPanel?
  private var observacao: AnyCancellable?
  private weak var central: AgentesCentral?
  private var inicioArrasto: (mouse: NSPoint, origem: NSPoint)?

  /// Mostra o painel enquanto houver sessão ou pedido; esconde (0 % de CPU) quando não há nada.
  func ligar(_ central: AgentesCentral) {
    guard observacao == nil else { return }
    self.central = central
    observacao = central.objectWillChange
      .receive(on: RunLoop.main)
      .sink { [weak self, weak central] _ in
        guard let self, let central else { return }
        self.atualizar(central)
      }
    atualizar(central)
  }

  func mostrar() {
    escondido = false
  }

  private func atualizar(_ central: AgentesCentral) {
    let comPedido = !central.pedidos.isEmpty
    let visivel = comPedido || (!central.quadro.sessoes.isEmpty && !escondido)
    guard visivel, let tela = (painel?.screen ?? NSScreen.main)?.visibleFrame else {
      painel?.orderOut(nil)
      return
    }
    let tamanho = AgentesPainelPosicao.tamanho(
      expandido: expandido, sessoes: central.quadro.sessoes.count, comPedido: comPedido)
    let canto = painel.map { NSPoint(x: $0.frame.maxX, y: $0.frame.minY) }
      ?? AgentesPainelPosicao.ler() ?? AgentesPainelPosicao.cantoPadrao(tela)
    let painel = self.painel ?? criarPainel(central)
    self.painel = painel
    painel.setFrame(AgentesPainelPosicao.quadro(canto: canto, tamanho: tamanho, tela: tela), display: true)
    painel.orderFrontRegardless()
  }

  private func criarPainel(_ central: AgentesCentral) -> NSPanel {
    let painel = CopilotPanel(
      contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    painel.isOpaque = false
    painel.backgroundColor = .clear
    painel.hasShadow = true
    painel.level = .floating
    painel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    painel.becomesKeyOnlyIfNeeded = true
    painel.hidesOnDeactivate = false
    painel.isReleasedWhenClosed = false
    painel.contentView = NSHostingView(rootView: AgentesIlha(central: central, controle: self))
    return painel
  }

  // MARK: - Arrastar (pelo mouse da tela: o gesto do SwiftUI mede em coordenadas da janela, que se move junto)

  func arrastar() {
    guard let painel else { return }
    let mouse = NSEvent.mouseLocation
    if inicioArrasto == nil { inicioArrasto = (mouse, painel.frame.origin) }
    guard let i = inicioArrasto else { return }
    painel.setFrameOrigin(NSPoint(x: i.origem.x + mouse.x - i.mouse.x, y: i.origem.y + mouse.y - i.mouse.y))
  }

  func soltar() {
    inicioArrasto = nil
    guard let painel else { return }
    AgentesPainelPosicao.gravar(NSPoint(x: painel.frame.maxX, y: painel.frame.minY))
  }
}

struct AgentesIlha: View {
  @ObservedObject var central: AgentesCentral
  @ObservedObject var controle: AgentesNotch
  @State private var sobre = false

  private var aberto: Bool { controle.expandido || !central.pedidos.isEmpty }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if aberto { cabecalho } else { pilula }
      if let pedido = central.pedidos.first {
        AgentesCartaoPermissao(pedido: pedido, naFila: central.pedidos.count - 1) {
          central.decidir(pedido.id, $0)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
      } else if aberto {
        ForEach(central.quadro.lista.prefix(6)) { sessao in
          HStack(spacing: 8) {
            JarvisMascote(estado: AgentesSessoesPagina.mascote(sessao.estado), tamanho: 14)
            Text(sessao.projeto).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            Text(sessao.estado.rotulo.lowercased())
              .font(.system(size: 11.5))
              .foregroundColor(JarvisHubTema.secundario)
              .lineLimit(1)
            Spacer(minLength: 0)
          }
          .frame(height: 30)
          .padding(.horizontal, 14)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .foregroundColor(JarvisHubTema.texto)
    .background(RoundedRectangle(cornerRadius: aberto ? 16 : 19, style: .continuous).fill(Color.black.opacity(0.92)))
    .overlay(RoundedRectangle(cornerRadius: aberto ? 16 : 19, style: .continuous).strokeBorder(JarvisHubTema.linha))
    .contentShape(Rectangle())
    .gesture(DragGesture(minimumDistance: 3).onChanged { _ in controle.arrastar() }.onEnded { _ in controle.soltar() })
    .onHover { dentro in
      sobre = dentro
      controle.expandido = dentro
    }
    .environment(\.colorScheme, .dark)
    .accessibilityIdentifier("agentes-painel")
  }

  private var pilula: some View {
    HStack(spacing: 8) {
      JarvisMascote(estado: central.estadoMascote, tamanho: 20)
      Text("\(central.quadro.sessoes.count)")
        .font(.system(size: 13, weight: .bold))
        .monospacedDigit()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onTapGesture { controle.expandido.toggle() }
    .accessibilityLabel("Agentes: \(central.quadro.sessoes.count) sessões")
  }

  private var cabecalho: some View {
    HStack(spacing: 10) {
      JarvisMascote(estado: central.estadoMascote, tamanho: 20)
      Text(linha)
        .font(.system(size: 12.5, weight: .medium))
        .lineLimit(1)
      Spacer(minLength: 0)
      Text("\(central.quadro.sessoes.count)")
        .font(.system(size: 12, weight: .bold))
        .monospacedDigit()
        .foregroundColor(JarvisHubTema.secundario)
      Button {
        controle.expandido = false
        controle.escondido = true
      } label: {
        Image(systemName: "eye.slash").font(.system(size: 11, weight: .medium))
      }
      .buttonStyle(.plain)
      .foregroundColor(JarvisHubTema.secundario)
      .help("Esconder; volta pelo menu da barra (Mostrar agentes)")
      .accessibilityIdentifier("agentes-painel-esconder")
    }
    .padding(.horizontal, 14)
    .frame(height: 44)
  }

  private var linha: String {
    if let pedido = central.pedidos.first { return "\(pedido.projeto) precisa de você" }
    guard let sessao = central.quadro.lista.first else { return "Jarvis" }
    return "\(sessao.projeto) · \(sessao.estado.rotulo.lowercased())"
  }
}

/// O cartão Permitir / Negar / Sempre, usado no notch e na página Sessões.
struct AgentesCartaoPermissao: View {
  let pedido: PedidoPermissao
  var naFila = 0
  let decidir: (DecisaoPermissao) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(pedido.ferramenta).font(.system(size: 13, weight: .bold))
        Text(pedido.projeto).font(.system(size: 12)).foregroundColor(JarvisHubTema.secundario)
        Spacer(minLength: 0)
        if naFila > 0 {
          Text("+\(naFila) na fila").font(.system(size: 11)).foregroundColor(JarvisHubTema.secundario)
        }
      }
      Text(pedido.resumo.isEmpty ? "Sem detalhes" : pedido.resumo)
        .font(.system(size: 12, design: .monospaced))
        .foregroundColor(Color(hex: 0xE1E3E6))
        .lineLimit(2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
      HStack(spacing: 8) {
        botao("Negar", cor: JarvisHubTema.vermelho) { decidir(.negar) }
        botao("Sempre", cor: JarvisHubTema.azul) { decidir(.sempre) }
        botao("Permitir", cor: JarvisHubTema.verde) { decidir(.permitir) }
      }
    }
  }

  private func botao(_ titulo: String, cor: Color, acao: @escaping () -> Void) -> some View {
    Button(action: acao) {
      Text(titulo)
        .font(.system(size: 12.5, weight: .semibold))
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(cor.opacity(0.22)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(cor.opacity(0.5)))
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

/// A página Sessões do hub: o que está rodando, o que espera você e como ligar os hooks.
struct AgentesSessoesPagina: View {
  @ObservedObject var central = AgentesCentral.shared
  @State private var ligados = AgentesHooks.ligados

  var body: some View {
    JarvisPaginaBase(
      titulo: "Sessões", subtitulo: "As sessões do Claude Code ao vivo e as permissões que esperam você.",
      cor: JarvisHubTema.azul
    ) {
      if !central.pedidos.isEmpty {
        JarvisRotulo("Esperando você")
        ForEach(central.pedidos) { pedido in
          JarvisCartao { AgentesCartaoPermissao(pedido: pedido) { central.decidir(pedido.id, $0) } }
        }
      }
      JarvisRotulo("Ao vivo")
      if central.quadro.sessoes.isEmpty {
        JarvisCartao {
          Text("Nenhuma sessão agora.")
            .font(.system(size: 13.5))
            .foregroundColor(JarvisHubTema.secundario)
        }
      }
      ForEach(central.quadro.lista) { sessao in
        JarvisCartao(padding: 14) {
          HStack(spacing: 12) {
            JarvisMascote(estado: Self.mascote(sessao.estado), tamanho: 22)
            VStack(alignment: .leading, spacing: 3) {
              Text(sessao.projeto).font(.system(size: 13.5, weight: .semibold))
              Text(sessao.passo.isEmpty ? sessao.estado.rotulo : "\(sessao.estado.rotulo) · \(sessao.passo)")
                .font(.system(size: 12))
                .foregroundColor(JarvisHubTema.secundario)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(sessao.atualizada.formatted(date: .omitted, time: .shortened))
              .font(.system(size: 11.5))
              .foregroundColor(JarvisHubTema.apagado)
          }
        }
      }
      JarvisRotulo("Hooks do Claude Code")
      JarvisCartao {
        Text(ligados ? "Ligados no ~/.claude/settings.json." : "Ainda não ligados.")
          .font(.system(size: 13.5, weight: .medium))
        Text("Para ligar (faz backup antes), rode no Terminal:")
          .font(.system(size: 12))
          .foregroundColor(JarvisHubTema.secundario)
        Text(verbatim: "\"\(AgentesCentral.caminhoLigar)\"")
          .font(.system(size: 12, design: .monospaced))
          .textSelection(.enabled)
        Text("Para desligar, o mesmo comando com --desligar.")
          .font(.system(size: 12))
          .foregroundColor(JarvisHubTema.secundario)
      }
    }
    .onAppear { ligados = AgentesHooks.ligados }
  }

  static func mascote(_ estado: EstadoSessao) -> JarvisEstadoMascote {
    switch estado {
    case .parada: return .parado
    case .pensando, .trabalhando: return .trabalhando
    case .terminou: return .terminou
    case .precisaDeVoce: return .precisaDeVoce
    case .erro: return .erro
    }
  }
}
