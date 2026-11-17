//
//  JarvisBarraLateral.swift — a barra lateral do app único: seções JARVIS e AGENTES, mais Ajustes.
//
//  Estilo portado do Coucou (MIT, © 2026 Louis Raillé, aviso em THIRD_PARTY_COUCOU_LICENSE):
//  `NotchBuddy/Sources/App/FlowHub.swift` (HubSidebar, HubSidebarHeader, HubSidebarItem).
//

import OmiTheme
import SwiftUI

/// Os itens da barra. Alguns abrem páginas que o Omi já tem (rotas do shell); os outros são
/// páginas do hub, desenhadas aqui.
enum JarvisPagina: String, CaseIterable, Identifiable {
  case hoje, conversas, tarefas, cerebro, estatisticas
  case sessoes, integracoes
  case ajustes

  var id: String { rawValue }

  static let jarvis: [JarvisPagina] = [.hoje, .conversas, .tarefas, .cerebro, .estatisticas]
  static let agentes: [JarvisPagina] = [.sessoes, .integracoes]

  var titulo: String {
    switch self {
    case .hoje: return "Hoje"
    case .conversas: return "Conversas"
    case .tarefas: return "Tarefas"
    case .cerebro: return "Cérebro"
    case .estatisticas: return "Estatísticas"
    case .sessoes: return "Sessões"
    case .integracoes: return "Integrações"
    case .ajustes: return "Ajustes"
    }
  }

  var simbolo: String {
    switch self {
    case .hoje: return "sun.max"
    case .conversas: return "text.bubble"
    case .tarefas: return "checklist"
    case .cerebro: return "brain"
    case .estatisticas: return "chart.bar"
    case .sessoes: return "terminal"
    case .integracoes: return "puzzlepiece.extension"
    case .ajustes: return "gearshape"
    }
  }

  /// Páginas desenhadas pelo hub; as demais abrem uma rota do Omi.
  var ehDoHub: Bool {
    switch self {
    case .tarefas, .cerebro, .estatisticas, .sessoes: return true
    case .hoje, .conversas, .integracoes, .ajustes: return false
    }
  }

  /// Qual item acender quando o shell está numa rota do Omi (navegação por automação, atalho, Esc).
  static func paraRota(_ rota: ChatFirstRoute, destinoMemoria: MemoryHubDestination?) -> JarvisPagina {
    switch rota {
    case .more(.apps): return .integracoes
    case .more(.settings), .more(.permissions): return .ajustes
    case .conversations: return .conversas
    case .memories where destinoMemoria == .conversations: return .conversas
    default: return .hoje
    }
  }
}

struct JarvisBarraLateral: View {
  let selecionada: JarvisPagina
  @ObservedObject var appState: AppState
  let escolher: (JarvisPagina) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 10) {
        JarvisMascote(estado: .parado, tamanho: 28)
        Text(verbatim: "Jarvis")
          .font(.system(size: 18, weight: .bold))
      }
      .padding(.horizontal, 8)
      .padding(.top, 25)
      .padding(.bottom, 16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
      // A barra de cima saiu; o cabeçalho é onde se arrasta a janela.
      .shellWindowDragHandle()

      ScrollView {
        VStack(alignment: .leading, spacing: 2) {
          JarvisCabecalhoSecao(texto: "Jarvis")
          ForEach(JarvisPagina.jarvis) { item($0) }
          JarvisCabecalhoSecao(texto: "Agentes").padding(.top, 14)
          ForEach(JarvisPagina.agentes) { item($0) }
        }
      }
      .scrollIndicators(.never)
      // Microfone e tela (o que a barra de cima mostrava) ficam no rodapé, ao lado dos Ajustes.
      HStack(spacing: 4) {
        item(.ajustes)
        ShellStatusIcons(appState: appState)
      }
      .padding(.top, 8)
    }
    .padding(.horizontal, 12)
    .padding(.bottom, 14)
    .frame(width: 210)
    .frame(maxHeight: .infinity)
    .background(JarvisHubTema.janela)
    .foregroundColor(JarvisHubTema.texto)
    .environment(\.colorScheme, .dark)
  }

  private func item(_ pagina: JarvisPagina) -> some View {
    JarvisItemBarra(pagina: pagina, selecionado: pagina == selecionada) { escolher(pagina) }
  }
}

private struct JarvisCabecalhoSecao: View {
  let texto: String

  var body: some View {
    Text(texto.uppercased())
      .font(.system(size: 10.5, weight: .bold))
      .tracking(1.2)
      .foregroundColor(JarvisHubTema.apagado)
      .padding(.horizontal, 10)
      .padding(.bottom, 4)
  }
}

private struct JarvisItemBarra: View {
  let pagina: JarvisPagina
  let selecionado: Bool
  let acao: () -> Void
  @State private var sobre = false

  var body: some View {
    Button(action: acao) {
      HStack(spacing: 10) {
        Image(systemName: pagina.simbolo)
          .font(.system(size: 14, weight: .medium))
          .frame(width: 20)
        Text(pagina.titulo)
          .font(.system(size: 14, weight: selecionado ? .semibold : .regular))
        Spacer(minLength: 0)
      }
      .foregroundColor(selecionado ? JarvisHubTema.texto : Color(hex: 0xB7BBC2))
      .padding(.horizontal, 10)
      .frame(height: 32)
      .background(
        RoundedRectangle(cornerRadius: 9)
          .fill(Color.white.opacity(selecionado ? 0.08 : (sobre ? 0.04 : 0))))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { sobre = $0 }
    .accessibilityIdentifier("jarvis-barra-\(pagina.rawValue)")
  }
}
