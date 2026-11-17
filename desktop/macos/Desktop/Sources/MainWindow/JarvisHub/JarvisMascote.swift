//
//  JarvisMascote.swift — o mascote do Jarvis: desenhado em código, ou a imagem da cópia local do
//  Coucou quando ela existe (ver JarvisSons.swift; nada dela entra no git).
//

import OmiTheme
import SwiftUI

/// O que o mascote está sentindo.
enum JarvisEstadoMascote: Equatable {
  case parado
  case trabalhando
  case terminou
  case precisaDeVoce
  case erro

  var cor: Color {
    switch self {
    case .parado: return Color(hex: 0xF5F6F8)
    case .trabalhando: return JarvisHubTema.azul
    case .terminou: return JarvisHubTema.verde
    case .precisaDeVoce: return JarvisHubTema.destaque
    case .erro: return JarvisHubTema.vermelho
    }
  }
}

/// Um corpo redondo com um visor: pisca parado, pula quando termina, pulsa quando precisa de
/// você e treme no erro.
struct JarvisMascote: View {
  var estado: JarvisEstadoMascote = .parado
  var tamanho: CGFloat = 28

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 30)) { linha in
      let t = linha.date.timeIntervalSinceReferenceDate
      corpo(t: t)
    }
    .frame(width: tamanho, height: tamanho)
    .accessibilityLabel("Jarvis")
  }

  private func corpo(t: Double) -> some View {
    let piscando = estado == .parado && t.truncatingRemainder(dividingBy: 4) < 0.12
    let pulo = estado == .terminou ? abs(sin(t * 6)) * tamanho * 0.18 : 0
    let tremor = estado == .erro ? sin(t * 40) * tamanho * 0.06 : 0
    let pulso = estado == .precisaDeVoce ? 1 + 0.08 * sin(t * 5) : 1
    let olhar = estado == .trabalhando ? sin(t * 2.5) * tamanho * 0.08 : 0

    return ZStack {
      if let imagem = JarvisSons.imagemLocal {
        // Com a cópia local, o personagem vem dela; o aro mostra o humor.
        Image(nsImage: imagem)
          .resizable()
          .scaledToFit()
          .overlay(
            Circle().strokeBorder(estado.cor.opacity(estado == .parado ? 0 : 0.9), lineWidth: tamanho * 0.08))
      } else {
        desenhado(piscando: piscando, olhar: olhar)
      }
    }
    .scaleEffect(pulso)
    .offset(x: tremor, y: -pulo)
  }

  private func desenhado(piscando: Bool, olhar: Double) -> some View {
    ZStack {
      Circle()
        .fill(
          LinearGradient(
            colors: [estado.cor, estado.cor.opacity(0.7)], startPoint: .top, endPoint: .bottom))
      Capsule()
        .fill(Color(hex: 0x111214))
        .frame(width: tamanho * 0.62, height: tamanho * (piscando ? 0.04 : 0.2))
        .overlay(
          HStack(spacing: tamanho * 0.16) {
            Circle().fill(estado.cor).frame(width: tamanho * 0.1)
            Circle().fill(estado.cor).frame(width: tamanho * 0.1)
          }
          .opacity(piscando ? 0 : 1)
          .offset(x: olhar)
        )
        .offset(y: -tamanho * 0.04)
    }
  }
}
