import Foundation

/// Trechos com nome da reunião que a extensão de reuniões está gravando, lidos pela mesma rota do
/// MCP de reuniões (`POST /api/mcp/reunioes`, ferramentas `listar_reunioes` e `consultar_transcricao`).
/// A chave do Cérebro da organização fica no cofre de segredos do app (Keychain, ou o arquivo de
/// segredos do fork sem Team ID); sem ela o copiloto fica só com a transcrição do Omi.
enum MeetingCopilotServer {
  static let endpoint = URL(string: "https://blog.smarten.digital/api/mcp/reunioes")!
  static let keyService = "com.omi.desktop.reunioes-smarten"
  static let keyAccount = "cerebro"
  /// Sem trecho novo por esse tempo, a reunião do servidor não é mais a chamada de agora.
  static let staleAfter: TimeInterval = 300

  struct Meeting: Equatable {
    let id: String
    let start: Date
  }

  struct Trecho: Equatable {
    let seq: Int
    let startMs: Int
    let speaker: String?
    let text: String
  }

  static var key: String? { DesktopKeychainStore.string(service: keyService, account: keyAccount) }

  // MARK: - Leitura das respostas (puro, testado)

  /// A reunião em andamento mais nova com fala recente. A "Omi dd/mm" é a do webhook do próprio Omi,
  /// sem nomes: usá-la seria mostrar a mesma transcrição duas vezes.
  // ponytail: chave de uma organização só; reunião gravada em outra organização não aparece
  static func active(in meetings: [[String: Any]], now: Date) -> Meeting? {
    for m in meetings {
      guard m["estado"] as? String == "em_andamento", let id = m["id"] as? String,
        let title = m["titulo"] as? String, !title.hasPrefix("Omi "),
        let start = (m["iniciada_em"] as? String).flatMap(date)
      else { continue }
      let covered = (m["coberto_ate_ms"] as? NSNumber)?.doubleValue ?? 0
      if now.timeIntervalSince(start.addingTimeInterval(covered / 1000)) < staleAfter {
        return Meeting(id: id, start: start)
      }
    }
    return nil
  }

  static func trechos(in result: [String: Any]) -> [Trecho] {
    (result["trechos"] as? [[String: Any]] ?? []).compactMap { t in
      guard let seq = (t["seq"] as? NSNumber)?.intValue, let text = t["texto"] as? String else { return nil }
      let speaker = (t["falante"] as? String)?.trimmingCharacters(in: .whitespaces)
      return Trecho(
        seq: seq, startMs: (t["inicio_ms"] as? NSNumber)?.intValue ?? 0,
        speaker: speaker?.isEmpty == false ? speaker : nil, text: text)
    }
  }

  /// O canal do microfone sai com o nome da conta do Meet; o primeiro nome basta para achar você.
  static func isMine(_ speaker: String?, givenName: String) -> Bool {
    let first = { (s: String) in
      s.split(separator: " ").first.map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
    }
    guard let speaker, let mine = first(givenName) else { return false }
    return first(speaker) == mine
  }

  /// "2026-11-14T18:34:59.673397+00:00": o ISO8601DateFormatter não lê seis casas de fração.
  static func date(_ text: String) -> Date? {
    let plain = text.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
    return ISO8601DateFormatter().date(from: plain)
  }

  // MARK: - Rede

  static func activeMeeting(key: String) async throws -> Meeting? {
    let result = try await call("listar_reunioes", ["estado": "em_andamento", "limite": 5], key: key)
    return active(in: result["reunioes"] as? [[String: Any]] ?? [], now: Date())
  }

  /// Uma página de trechos confirmados depois de `after`, e se ainda há mais.
  static func trechos(meeting: String, after: Int?, key: String) async throws -> (items: [Trecho], more: Bool) {
    var args: [String: Any] = ["id": meeting, "limite": 200]
    if let after { args["apos_seq"] = after }
    let result = try await call("consultar_transcricao", args, key: key)
    return (trechos(in: result), result["proximo_apos_seq"] is NSNumber)
  }

  private static func call(_ tool: String, _ args: [String: Any], key: String) async throws -> [String: Any] {
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.timeoutInterval = 15
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    request.httpBody = try JSONSerialization.data(withJSONObject: [
      "jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": ["name": tool, "arguments": args],
    ])
    let (data, response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200,
      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let result = json["result"] as? [String: Any], result["isError"] as? Bool != true,
      let content = result["structuredContent"] as? [String: Any]
    else { throw URLError(.badServerResponse) }
    return content
  }
}
