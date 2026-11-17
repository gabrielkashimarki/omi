//
//  JarvisSons.swift — sons e imagem do mascote, lidos da cópia local do Coucou na hora de rodar.
//
//  Os sons, o ícone e o personagem do Coucou não são MIT (LICENSE-ASSETS.md de lá) e este
//  repositório é público: nada disso entra no git. Sem a cópia local, o mascote é o Jarvis
//  desenhado em código e o app fica mudo.
//

import AppKit

@MainActor
enum JarvisSons {
  static let pastaLocal = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("omi-fork/referencias/coucou/NotchBuddy", isDirectory: true)

  /// A imagem do personagem (o ícone do app), nil sem a cópia local.
  static let imagemLocal: NSImage? = NSImage(
    contentsOf: pastaLocal.appendingPathComponent("Assets.xcassets/AppIcon.appiconset/icon_256x256.png"))

  private static var tocando: [String: NSSound] = [:]

  /// O som de cada reação do mascote.
  static func nomeDoSom(_ estado: JarvisEstadoMascote) -> String? {
    switch estado {
    case .terminou: return "finish"
    case .precisaDeVoce: return "approval"
    case .erro: return "error"
    case .trabalhando, .parado: return nil
    }
  }

  static func reagir(_ estado: JarvisEstadoMascote) {
    guard let nome = nomeDoSom(estado) else { return }
    tocar(nome)
  }

  static func tocar(_ nome: String) {
    if let som = tocando[nome] {
      som.stop()
      som.play()
      return
    }
    let arquivo = pastaLocal.appendingPathComponent("Resources/sounds/\(nome).wav")
    guard let som = NSSound(contentsOf: arquivo, byReference: true) else { return }
    tocando[nome] = som
    som.play()
  }
}
