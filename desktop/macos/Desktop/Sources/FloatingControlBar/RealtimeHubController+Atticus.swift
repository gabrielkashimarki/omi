import Foundation

// Fork: o motor do Atticus vem embutido em Contents/Resources/atticus (atticus.py + binário Atticus,
// usado só como "mãos" por linha de comando). A voz do Omi repassa o pedido e fala o resultado.
extension RealtimeHubController {
  // ponytail: corte fixo para caber no contexto da voz.
  static let atticusLimiteCaracteres = 2000
  static let atticusTempoMaximo: TimeInterval = 180

  nonisolated static var atticusPasta: URL? {
    Bundle.main.resourceURL?.appendingPathComponent("atticus", isDirectory: true)
  }

  func mexerNoMac(pedido: String) async -> AuthorizedRealtimeToolExecutionResult {
    guard let pasta = Self.atticusPasta,
      FileManager.default.fileExists(atPath: pasta.appendingPathComponent("atticus.py").path)
    else { return .succeeded("O motor do Atticus não está instalado dentro do Omi.") }
    let t0 = Date()
    let (saida, codigo) = await Self.rodarAtticus(pedido: pedido, pasta: pasta)
    log("RealtimeHub: mexer_no_mac terminou com \(codigo) em \(Int(Date().timeIntervalSince(t0)))s (\(saida.count) chars)")
    if saida.isEmpty {
      return .succeeded(codigo == 0 ? "Feito." : "O Atticus não conseguiu fazer isso (código \(codigo)).")
    }
    return .succeeded(String(saida.suffix(Self.atticusLimiteCaracteres)))
  }

  /// Mesmo jeito que o app do Atticus chama o motor: `/bin/sh atticus.py` (o cabeçalho sh escolhe o python3).
  nonisolated static func rodarAtticus(pedido: String, pasta: URL) async -> (String, Int32) {
    await withCheckedContinuation { continuacao in
      let p = Process()
      p.executableURL = URL(fileURLWithPath: "/bin/sh")
      p.arguments = [pasta.appendingPathComponent("atticus.py").path, pedido]
      var env = ProcessInfo.processInfo.environment
      env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
      env["ATTICUS_APP"] = pasta.appendingPathComponent("Atticus").path
      env["ATTICUS_RESOURCES_DIR"] = pasta.path
      p.environment = env
      let cano = Pipe()
      p.standardOutput = cano
      p.standardError = FileHandle.nullDevice
      let relogio = DispatchWorkItem { if p.isRunning { p.terminate() } }
      p.terminationHandler = { processo in
        relogio.cancel()
        let dados = cano.fileHandleForReading.readDataToEndOfFile()
        let texto = String(decoding: dados, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        continuacao.resume(returning: (texto, processo.terminationStatus))
      }
      do {
        try p.run()
        DispatchQueue.global().asyncAfter(deadline: .now() + atticusTempoMaximo, execute: relogio)
      } catch {
        continuacao.resume(returning: ("Não consegui abrir o motor do Atticus: \(error.localizedDescription)", -1))
      }
    }
  }
}
