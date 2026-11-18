import Foundation
import GRDB

/// O que o Omi gravou neste Mac (conversas, transcrição e memórias), para o cérebro do Jarvis no servidor ler pelo
/// `/jarvis/mac`. Só leitura, direto no `omi.db`: o MCP do Omi na nuvem não tem as conversas do fork (vazio em 18/11) e
/// o `getLocalConversations` só devolve as já sincronizadas.
enum JarvisOmi {
  static let formatos =
    "Formatos: {\"omi\":\"conversas\",\"dia\":\"AAAA-MM-DD\"} (padrão hoje), {\"omi\":\"conversa\",\"id\":123} "
    + "(transcrição inteira), {\"omi\":\"buscar\",\"texto\":\"...\",\"dias\":7} e {\"omi\":\"memorias\",\"texto\":\"...\"}."
  /// Teto do texto devolvido ao servidor, para não estourar a mensagem do socket nem o contexto do Claude.
  static let limite = 60_000

  @MainActor static func consultar(_ pedido: [String: Any]) async -> [String: Any] {
    guard let pool = await RewindDatabase.shared.getDatabaseQueue() else {
      return ["ok": false, "mensagem": "O banco do Omi não está aberto (sem login no Omi?)."]
    }
    let tipo = (pedido["omi"] as? String ?? "").lowercased()
    // só valores Sendable entram na leitura do banco
    let dia = pedido["dia"] as? String
    let id = (pedido["id"] as? Int) ?? Int("\(pedido["id"] ?? "")")
    let busca = pedido["texto"] as? String ?? ""
    let dias = pedido["dias"] as? Int ?? 7
    do {
      let texto = try await pool.read { db -> String in
        switch tipo {
        case "conversas": return try conversas(db, dia: dia)
        case "conversa":
          guard let id else { return "Falta o id. " + formatos }
          return try conversa(db, id: Int64(id))
        case "buscar": return try buscar(db, texto: busca, dias: dias)
        case "memorias", "memórias": return try memorias(db, texto: busca)
        default: return "Não conheço \"\(tipo)\". " + formatos
        }
      }
      return ["ok": true, "mensagem": String(texto.prefix(limite))]
    } catch {
      return ["ok": false, "mensagem": "Falhou ao ler o Omi: \(error.localizedDescription)"]
    }
  }

  /// Início e fim do dia local (AAAA-MM-DD; nil = hoje).
  static func intervalo(dia: String?, agora: Date = Date()) -> (Date, Date)? {
    let cal = Calendar.current
    var inicio = cal.startOfDay(for: agora)
    if let dia, !dia.isEmpty {
      let f = DateFormatter()
      f.locale = Locale(identifier: "en_US_POSIX")
      f.dateFormat = "yyyy-MM-dd"
      guard let d = f.date(from: dia) else { return nil }
      inicio = cal.startOfDay(for: d)
    }
    guard let fim = cal.date(byAdding: .day, value: 1, to: inicio) else { return nil }
    return (inicio, fim)
  }

  private static let hora: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "dd/MM HH:mm"
    return f
  }()

  private static func conversas(_ db: Database, dia: String?) throws -> String {
    guard let (inicio, fim) = intervalo(dia: dia) else { return "Dia inválido, use AAAA-MM-DD." }
    let linhas = try Row.fetchAll(
      db,
      sql: """
        SELECT s.id, s.title, s.overview, s.startedAt, s.finishedAt,
          (SELECT COUNT(*) FROM transcription_segments g WHERE g.sessionId = s.id) AS trechos
        FROM transcription_sessions s
        WHERE COALESCE(s.deleted, 0) = 0 AND COALESCE(s.discarded, 0) = 0 AND s.startedAt >= ? AND s.startedAt < ?
        ORDER BY s.startedAt
        """, arguments: [inicio, fim])
    guard !linhas.isEmpty else { return "Nenhuma conversa gravada pelo Omi nesse dia." }
    return linhas.map { r -> String in
      let comeco: Date = r["startedAt"]
      let termino: Date? = r["finishedAt"]
      let minutos = termino.map { " (\(Int($0.timeIntervalSince(comeco) / 60)) min)" } ?? " (em andamento)"
      let titulo: String = r["title"] ?? "sem título"
      let resumo: String = r["overview"] ?? ""
      let trechos: Int = r["trechos"]
      return "id \(r["id"] as Int64) | \(hora.string(from: comeco))\(minutos) | \(titulo) | \(trechos) trechos"
        + (resumo.isEmpty ? "" : "\n  \(resumo.prefix(400))")
    }.joined(separator: "\n")
  }

  private static func conversa(_ db: Database, id: Int64) throws -> String {
    guard
      let s = try Row.fetchOne(
        db, sql: "SELECT title, overview, startedAt FROM transcription_sessions WHERE id = ?", arguments: [id])
    else { return "Conversa \(id) não existe." }
    let trechos = try Row.fetchAll(
      db,
      sql: "SELECT isUser, speakerLabel, text FROM transcription_segments WHERE sessionId = ? ORDER BY segmentOrder",
      arguments: [id])
    let comeco: Date = s["startedAt"]
    let titulo: String = s["title"] ?? "sem título"
    let cabeca = "\(titulo) | \(hora.string(from: comeco))\n\(s["overview"] as String? ?? "")\n"
    return cabeca
      + trechos.map { r in
        let eu: Bool = r["isUser"]
        let quem: String = eu ? "Gabriel" : (r["speakerLabel"] as String? ?? "outro")
        return "\(quem): \(r["text"] as String)"
      }.joined(separator: "\n")
  }

  private static func buscar(_ db: Database, texto: String, dias: Int) throws -> String {
    let t = texto.trimmingCharacters(in: .whitespaces)
    guard !t.isEmpty else { return "Falta o texto. " + formatos }
    let desde = Date().addingTimeInterval(-Double(max(1, dias)) * 86_400)
    let linhas = try Row.fetchAll(
      db,
      sql: """
        SELECT s.id, s.title, s.startedAt, g.text FROM transcription_segments g
        JOIN transcription_sessions s ON s.id = g.sessionId
        WHERE COALESCE(s.deleted, 0) = 0 AND s.startedAt >= ? AND g.text LIKE ? ESCAPE '\\'
        ORDER BY s.startedAt DESC, g.segmentOrder LIMIT 60
        """,
      arguments: [
        desde, "%" + t.replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_") + "%",
      ])
    guard !linhas.isEmpty else { return "Nada com \"\(t)\" nas conversas dos últimos \(dias) dias." }
    return linhas.map { r in
      let comeco: Date = r["startedAt"]
      return "id \(r["id"] as Int64) | \(hora.string(from: comeco)) | \(r["title"] as String? ?? "sem título"): "
        + "\(r["text"] as String)"
    }.joined(separator: "\n")
  }

  private static func memorias(_ db: Database, texto: String) throws -> String {
    let t = texto.trimmingCharacters(in: .whitespaces)
    let filtro = t.isEmpty ? "" : "AND content LIKE ? ESCAPE '\\'"
    let args: StatementArguments =
      t.isEmpty
      ? [] : ["%" + t.replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_") + "%"]
    let linhas = try Row.fetchAll(
      db,
      sql: "SELECT content, category FROM memories WHERE COALESCE(deleted, 0) = 0 \(filtro) ORDER BY id DESC LIMIT 80",
      arguments: args)
    guard !linhas.isEmpty else { return "Nenhuma memória\(t.isEmpty ? "" : " com \"\(t)\"")." }
    return linhas.map { "[\($0["category"] as String)] \($0["content"] as String)" }.joined(separator: "\n")
  }
}
