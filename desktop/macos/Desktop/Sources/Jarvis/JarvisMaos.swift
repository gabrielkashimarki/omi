import AppKit
import Foundation

/// Mãos no Mac para o `mexer_no_mac` do Jarvis. O pedido é o JSON que o Claude monta no Fly; aceita os formatos
/// abaixo (chaves em português ou inglês) e devolve "não sei fazer isso ainda" com a lista, para ele tentar de novo.
enum JarvisMaos {
  enum Acao: Equatable {
    case abrirApp(String)
    case abrirURL(URL)
    case digitar(String)
    case hands([String])  // verbos do `Atticus --hands`: see, click, type, press, scroll, menu, wait...
    case desconhecida
  }

  static let formatos =
    "Formatos aceitos: {\"acao\":\"abrir_app\",\"app\":\"Calculadora\"}, {\"acao\":\"abrir_url\",\"url\":\"https://...\"}, "
    + "{\"acao\":\"digitar\",\"texto\":\"...\"} ou {\"args\":[\"click\",\"Enviar\"]} (verbos do Atticus --hands: "
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
        return falha("O Omi Fork não tem permissão de Acessibilidade para digitar. O Gabriel precisa liberar nos Ajustes.")
      }
      digitar(texto)
      return ok("Digitei \(texto.count) caracteres no app da frente.")
    case .hands(let args):
      return await hands(args)
    case .desconhecida:
      return falha("Não sei fazer isso ainda. " + formatos)
    }
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
    return codigo == 0 ? ok(texto.isEmpty ? "Feito." : texto) : falha(texto.isEmpty ? "Atticus saiu com \(codigo)." : texto)
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
