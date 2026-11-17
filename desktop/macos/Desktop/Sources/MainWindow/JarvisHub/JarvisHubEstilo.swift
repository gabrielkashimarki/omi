//
//  JarvisHubEstilo.swift — cores, cartões e cabeçalho do hub do Jarvis.
//
//  Portado do Coucou (MIT, © 2026 Louis Raillé, aviso em THIRD_PARTY_COUCOU_LICENSE):
//  `NotchBuddy/Sources/App/FlowHub.swift` (HubTheme, HubCard, HubLabel, HubPageScaffold) e
//  `NotchBuddy/Sources/App/FlowHubMochis.swift` (HubHero, HubHeroLight, HubHeroBackdrop).
//  Só o código veio; nome, personagem e mídia do Coucou não entram aqui.
//

import OmiTheme
import QuartzCore
import SwiftUI

/// As cores do hub: preto da ilha, laranja de destaque.
enum JarvisHubTema {
  static let janela = Color.black
  static let painel = Color(hex: 0x0E0F11)
  static let cartao = Color(hex: 0x18191C)
  static let linha = Color.white.opacity(0.07)
  static let texto = Color(hex: 0xF5F6F8)
  static let secundario = Color(hex: 0x8E939C)
  static let apagado = Color(hex: 0x6B7079)
  static let destaque = Color(hex: 0xFB923C)
  static let verde = Color(hex: 0x34D399)
  static let vermelho = Color(hex: 0xFF453A)
  static let azul = Color(hex: 0x3B9EFF)
}

/// Cartão escuro arredondado.
struct JarvisCartao<Content: View>: View {
  var padding: CGFloat = 18
  @ViewBuilder var content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: 12) { content() }
      .padding(padding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(JarvisHubTema.cartao))
      .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(JarvisHubTema.linha))
  }
}

/// Versaletes pequenas acima de uma lista ("HOJE").
struct JarvisRotulo: View {
  let texto: String
  init(_ texto: String) { self.texto = texto }

  var body: some View {
    Text(texto.uppercased())
      .font(.system(size: 11.5, weight: .bold))
      .tracking(1.3)
      .foregroundColor(JarvisHubTema.apagado)
  }
}

/// Uma página do hub: cabeçalho com gradiente e o conteúdo rolando, dentro do painel escuro.
struct JarvisPaginaBase<Trailing: View, Content: View>: View {
  let titulo: String
  var subtitulo: String? = nil
  var cor: Color = JarvisHubTema.destaque
  @ViewBuilder var trailing: () -> Trailing
  @ViewBuilder var content: () -> Content

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        JarvisCabecalho(titulo: titulo, subtitulo: subtitulo, cor: cor, trailing: trailing)
        content()
      }
      .padding(.horizontal, 28)
      .padding(.top, 24)
      .padding(.bottom, 28)
      .frame(maxWidth: 1100, alignment: .leading)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(JarvisHubTema.painel))
    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(JarvisHubTema.linha))
    .padding(10)
    .foregroundColor(JarvisHubTema.texto)
    .environment(\.colorScheme, .dark)
    .tint(JarvisHubTema.destaque)
  }
}

extension JarvisPaginaBase where Trailing == EmptyView {
  init(
    titulo: String, subtitulo: String? = nil, cor: Color = JarvisHubTema.destaque,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.titulo = titulo
    self.subtitulo = subtitulo
    self.cor = cor
    self.trailing = { EmptyView() }
    self.content = content
  }
}

/// Página que ainda não existe (fase 4).
struct JarvisEmBreve: View {
  let titulo: String
  let texto: String

  var body: some View {
    JarvisPaginaBase(titulo: titulo, subtitulo: "Em breve", cor: JarvisHubTema.secundario) {
      JarvisCartao {
        Text(texto)
          .font(.system(size: 13.5))
          .foregroundColor(JarvisHubTema.secundario)
      }
    }
  }
}

/// O topo de uma página: faixa colorida com título, linha de apoio, ação e o mascote à direita.
struct JarvisCabecalho<Trailing: View>: View {
  let titulo: String
  var subtitulo: String?
  var cor: Color
  @ViewBuilder var trailing: () -> Trailing
  @StateObject private var luz = JarvisLuzCabecalho()

  var body: some View {
    ZStack(alignment: .bottomTrailing) {
      JarvisFundoCabecalho(cor: cor, luz: luz)
        .allowsHitTesting(false)
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 8) {
          Text(titulo)
            .font(.system(size: 30, weight: .bold))
            .tracking(-0.6)
          if let subtitulo {
            Text(subtitulo)
              .font(.system(size: 14))
              .foregroundColor(Color(hex: 0xB7BBC2))
              .fixedSize(horizontal: false, vertical: true)
              .frame(maxWidth: 420, alignment: .leading)
          }
          Spacer(minLength: 0)
          trailing()
        }
        .padding(26)
        Spacer(minLength: 0)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .frame(height: 170)
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(cor.opacity(0.16)))
    .onContinuousHover { fase in
      switch fase {
      case .active(let ponto): luz.alvo = ponto
      case .ended: luz.alvo = nil
      }
    }
  }
}

/// A luz e as partículas da faixa, movidas quadro a quadro sem redesenhar a página.
@MainActor
final class JarvisLuzCabecalho: ObservableObject {
  struct Particula {
    var x: CGFloat, y: CGFloat
    var vx: CGFloat, vy: CGFloat
    var px: CGFloat = 0, py: CGFloat = 0
    var raio: CGFloat
    var fase: CGFloat
    var profundidade: CGFloat
    var branca: Bool
  }

  var alvo: CGPoint?
  private(set) var posicao: CGPoint?
  private(set) var forca: CGFloat = 0
  private(set) var particulas: [Particula] = []
  private var tamanho: CGSize = .zero
  private var ultimo = CACurrentMediaTime()
  let inicio = CACurrentMediaTime()

  func passo(tamanho: CGSize) {
    let agora = CACurrentMediaTime()
    let dt = CGFloat(min(0.05, max(0, agora - ultimo)))
    ultimo = agora
    if tamanho != self.tamanho { reiniciar(tamanho) }

    if let alvo {
      let de = posicao ?? alvo
      let k = min(1, dt * 9)
      posicao = CGPoint(x: de.x + (alvo.x - de.x) * k, y: de.y + (alvo.y - de.y) * k)
      forca = min(1, forca + dt * 3.5)
    } else {
      forca = max(0, forca - dt * 1.6)
    }

    let t = CGFloat(agora - inicio)
    for i in particulas.indices {
      var p = particulas[i]
      if let pos = posicao, forca > 0.01 {
        let dx = p.x - pos.x, dy = p.y - pos.y
        let d = max(1, hypot(dx, dy))
        if d < 120 {
          let empurrao = pow(1 - d / 120, 2) * 220 * forca * p.profundidade
          p.px += dx / d * empurrao * dt
          p.py += dy / d * empurrao * dt
        }
      }
      p.px *= max(0, 1 - dt * 2.2)
      p.py *= max(0, 1 - dt * 2.2)
      p.x += (p.vx + sin(t * 0.7 + p.fase) * 5 * p.profundidade) * dt + p.px * dt * 6
      p.y += p.vy * dt + p.py * dt * 6
      if p.y < -6 { p.y = tamanho.height + 6; p.x = CGFloat.random(in: 0...max(1, tamanho.width)) }
      if p.y > tamanho.height + 8 { p.y = -4 }
      if p.x < -8 { p.x = tamanho.width + 6 }
      if p.x > tamanho.width + 8 { p.x = -6 }
      particulas[i] = p
    }
  }

  private func reiniciar(_ tamanho: CGSize) {
    self.tamanho = tamanho
    let quantidade = Int(min(110, max(18, tamanho.width * tamanho.height / 3600)))
    particulas = (0..<quantidade).map { _ in
      let profundidade = CGFloat.random(in: 0.4...1)
      return Particula(
        x: .random(in: 0...max(1, tamanho.width)), y: .random(in: 0...max(1, tamanho.height)),
        vx: CGFloat.random(in: -3...3) * profundidade, vy: CGFloat.random(in: -13 ... -3) * profundidade,
        raio: .random(in: 0.5...1.5) * (0.6 + profundidade * 0.7),
        fase: .random(in: 0...(2 * .pi)), profundidade: profundidade, branca: Int.random(in: 0..<9) == 0)
    }
  }
}

/// Fundo da faixa: preto profundo, a cor da página respirando num canto e partículas subindo.
struct JarvisFundoCabecalho: View {
  let cor: Color
  let luz: JarvisLuzCabecalho

  var body: some View {
    // ponytail: 30 quadros por segundo fixos; pausar quando a janela some, se pesar.
    TimelineView(.animation(minimumInterval: 1.0 / 30)) { linha in
      Canvas { contexto, tamanho in
        _ = linha.date
        luz.passo(tamanho: tamanho)
        let ret = CGRect(origin: .zero, size: tamanho)
        let t = CGFloat(CACurrentMediaTime() - luz.inicio)

        contexto.fill(Path(ret), with: .color(Color(hex: 0x020203)))
        contexto.fill(
          Path(ret),
          with: .linearGradient(
            Gradient(colors: [cor.opacity(0.10), .clear]),
            startPoint: CGPoint(x: tamanho.width, y: 0),
            endPoint: CGPoint(x: tamanho.width * 0.35, y: tamanho.height)))
        let respiro = 0.85 + 0.15 * sin(t * 0.9)
        contexto.fill(
          Path(ret),
          with: .radialGradient(
            Gradient(colors: [cor.opacity(0.30 * respiro), cor.opacity(0.08), .clear]),
            center: CGPoint(x: tamanho.width * 0.92, y: -tamanho.height * 0.15),
            startRadius: 0, endRadius: max(tamanho.width, tamanho.height) * 0.55 * respiro))

        for p in luz.particulas {
          var alfa = (0.22 + 0.5 * (0.5 + 0.5 * sin(t * (1.2 + p.profundidade) + p.fase))) * p.profundidade
          var raio = p.raio
          if let pos = luz.posicao, luz.forca > 0.01 {
            let d = hypot(p.x - pos.x, p.y - pos.y)
            if d < 200 {
              let perto = (1 - d / 200) * luz.forca
              alfa += perto * 0.6
              raio *= 1 + perto * 0.8
            }
          }
          let tinta = p.branca ? Color.white : cor
          let ponto = CGRect(x: p.x - raio, y: p.y - raio, width: raio * 2, height: raio * 2)
          if raio > 1.1 {
            contexto.fill(
              Path(ellipseIn: ponto.insetBy(dx: -raio * 1.6, dy: -raio * 1.6)),
              with: .color(tinta.opacity(min(1, alfa) * 0.12)))
          }
          contexto.fill(Path(ellipseIn: ponto), with: .color(tinta.opacity(min(1, alfa))))
        }
      }
    }
  }
}
