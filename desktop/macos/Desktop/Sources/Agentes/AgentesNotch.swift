//
//  AgentesNotch.swift — a ilha preta no notch: o mascote, as sessões e o cartão de permissão.
//
//  Portado do Coucou (MIT, © 2026 Louis Raillé, aviso em THIRD_PARTY_COUCOU_LICENSE):
//  `NotchBuddy/Sources/App/IslandWindowController.swift` (painel sem borda acima da barra de menus)
//  e o cartão de aprovação de `NotchBuddy/Sources/App/IslandViewContent.swift`, bem simplificados.
//

import AppKit
import Combine
import OmiTheme
import SwiftUI

@MainActor
final class AgentesNotch {
  static let shared = AgentesNotch()

  private var painel: NSPanel?
  private var observacao: AnyCancellable?

  /// Mostra a ilha enquanto houver sessão ou pedido; esconde (0 % de CPU) quando não há nada.
  func ligar(_ central: AgentesCentral) {
    guard observacao == nil else { return }
    observacao = central.objectWillChange
      .receive(on: RunLoop.main)
      .sink { [weak self, weak central] _ in
        guard let self, let central else { return }
        self.atualizar(central)
      }
    atualizar(central)
  }

  private func atualizar(_ central: AgentesCentral) {
    let visivel = !central.quadro.sessoes.isEmpty || !central.pedidos.isEmpty
    guard visivel, let tela = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main
    else {
      painel?.orderOut(nil)
      return
    }
    let notch = tela.safeAreaInsets.top
    let tamanho = NSSize(
      width: central.pedidos.isEmpty ? 300 : 400,
      height: notch + 34 + (central.pedidos.isEmpty ? 0 : 128))
    let topo = notch > 0 ? tela.frame.maxY : tela.visibleFrame.maxY
    let quadro = NSRect(
      x: tela.frame.midX - tamanho.width / 2, y: topo - tamanho.height, width: tamanho.width,
      height: tamanho.height)

    let painel = self.painel ?? criarPainel(central, notch: notch)
    self.painel = painel
    painel.setFrame(quadro, display: true)
    painel.orderFrontRegardless()
  }

  private func criarPainel(_ central: AgentesCentral, notch: CGFloat) -> NSPanel {
    let painel = NSPanel(
      contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    painel.isOpaque = false
    painel.backgroundColor = .clear
    painel.hasShadow = false
    painel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
    painel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    painel.becomesKeyOnlyIfNeeded = true
    painel.isReleasedWhenClosed = false
    painel.contentView = NSHostingView(rootView: AgentesIlha(central: central, alturaNotch: notch))
    return painel
  }
}

struct AgentesIlha: View {
  @ObservedObject var central: AgentesCentral
  let alturaNotch: CGFloat

  var body: some View {
    VStack(spacing: 0) {
      Color.clear.frame(height: alturaNotch)
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
      }
      .padding(.horizontal, 14)
      .frame(height: 34)
      if let pedido = central.pedidos.first {
        AgentesCartaoPermissao(pedido: pedido, naFila: central.pedidos.count - 1) {
          central.decidir(pedido.id, $0)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .foregroundColor(JarvisHubTema.texto)
    .background(
      UnevenRoundedRectangle(bottomLeadingRadius: 18, bottomTrailingRadius: 18, style: .continuous)
        .fill(Color.black))
    .environment(\.colorScheme, .dark)
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
