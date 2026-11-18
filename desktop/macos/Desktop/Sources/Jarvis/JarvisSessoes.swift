import Foundation

/// Sessões do Claude Code deste Mac (terminal e aba Code do Claude desktop), lidas das transcrições em
/// `~/.claude/projects`, para o cérebro do Jarvis ver o que cada uma está fazendo e abrir uma nova. Só texto de quem
/// fala (pedido e resposta): saída de ferramenta fica de fora, porque é onde segredo costuma aparecer.
enum JarvisSessoes {
  static let formatos =
    "Formatos: {\"sessoes\":\"listar\",\"horas\":24}, {\"sessoes\":\"ler\",\"id\":\"<id>\",\"n\":12} e "
    + "{\"sessoes\":\"nova\",\"pasta\":\"/Users/.../projeto\",\"pedido\":\"...\"}."
  /// Lê só o fim do arquivo: transcrição longa passa de dezenas de MB.
  static let fimLido = 600_000
  static let claude = "/opt/homebrew/bin/claude"

  static var raiz: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects") }

  @MainActor static func consultar(_ pedido: [String: Any]) async -> [String: Any] {
    // só valores Sendable vão para fora do main: ler transcrição grande travaria a tela
    let tipo = (pedido["sessoes"] as? String ?? "").lowercased()
    let horas = pedido["horas"] as? Double ?? 24
    let id = pedido["id"] as? String
    let n = pedido["n"] as? Int ?? 12
    let pasta = pedido["pasta"] as? String ?? ""
    let texto = pedido["pedido"] as? String ?? ""
    let r = await Task.detached { () -> (Bool, String) in
      switch tipo {
      case "listar": return (true, listar(horas: horas))
      case "ler":
        guard let id, let url = acharSessao(id) else { return (false, "Sessão não achada.") }
        return (true, ler(url, n: n))
      case "nova": return nova(pasta: pasta, texto: texto)
      default: return (false, "Não conheço \"\(tipo)\". " + formatos)
      }
    }.value
    return ["ok": r.0, "mensagem": r.1]
  }

  /// Arquivos de sessão (fora as transcrições de subagente), do mais recente para o mais antigo.
  static func arquivos(desde: Date) -> [(url: URL, data: Date)] {
    let fm = FileManager.default
    var achados: [(URL, Date)] = []
    for pasta in (try? fm.contentsOfDirectory(at: raiz, includingPropertiesForKeys: nil)) ?? [] {
      for url in (try? fm.contentsOfDirectory(at: pasta, includingPropertiesForKeys: [.contentModificationDateKey]))
        ?? [] where url.pathExtension == "jsonl"
      {
        let data = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let data, data >= desde { achados.append((url, data)) }
      }
    }
    return achados.sorted { $0.1 > $1.1 }
  }

  static func acharSessao(_ id: String) -> URL? {
    let limpo = id.trimmingCharacters(in: .whitespaces)
    guard !limpo.isEmpty, !limpo.contains("/") else { return nil }
    return arquivos(desde: .distantPast).first { $0.url.deletingPathExtension().lastPathComponent.hasPrefix(limpo) }?
      .url
  }

  /// Resumo de uma transcrição (puro sobre as linhas, testado).
  struct Resumo: Equatable {
    var titulo: String?
    var pasta: String?
    var origem: String?
    var falas: [(quem: String, texto: String)] = []

    static func == (a: Resumo, b: Resumo) -> Bool {
      a.titulo == b.titulo && a.pasta == b.pasta && a.origem == b.origem
        && a.falas.map { "\($0.quem):\($0.texto)" } == b.falas.map { "\($0.quem):\($0.texto)" }
    }

    init(linhas: [Substring]) {
      for l in linhas {
        guard let j = (try? JSONSerialization.jsonObject(with: Data(l.utf8))) as? [String: Any] else { continue }
        let tipo = j["type"] as? String
        if tipo == "custom-title", let t = j["customTitle"] as? String { titulo = t }
        if let c = j["cwd"] as? String { pasta = c }
        if let e = j["entrypoint"] as? String { origem = e }
        guard tipo == "user" || tipo == "assistant", j["isSidechain"] as? Bool != true,
          let m = j["message"] as? [String: Any]
        else { continue }
        let texto: String
        if let s = m["content"] as? String {
          texto = s
        } else {
          let partes = m["content"] as? [[String: Any]] ?? []
          texto = partes.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }
            .joined(separator: "\n")
        }
        let t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        // aviso do sistema e lembrete entram como "user" na transcrição: não são o Gabriel
        guard !t.isEmpty, !t.hasPrefix("<") else { continue }
        falas.append((tipo == "user" ? "Gabriel" : "Claude", t))
      }
    }
  }

  static func resumo(_ url: URL) -> Resumo {
    guard let h = try? FileHandle(forReadingFrom: url) else { return Resumo(linhas: []) }
    defer { try? h.close() }
    let tamanho = (try? h.seekToEnd()) ?? 0
    try? h.seek(toOffset: tamanho > UInt64(fimLido) ? tamanho - UInt64(fimLido) : 0)
    let texto = String(decoding: h.readDataToEndOfFile(), as: UTF8.self)
    var linhas = texto.split(separator: "\n")
    if tamanho > UInt64(fimLido), !linhas.isEmpty { linhas.removeFirst() }  // a primeira veio cortada
    return Resumo(linhas: linhas)
  }

  private static func listar(horas: Double) -> String {
    let agora = Date()
    let lista = arquivos(desde: agora.addingTimeInterval(-max(1, horas) * 3600)).prefix(25)
    guard !lista.isEmpty else { return "Nenhuma sessão do Claude Code nas últimas \(Int(horas)) h." }
    let hora = DateFormatter()
    hora.dateFormat = "dd/MM HH:mm"
    return lista.map { item -> String in
      let r = resumo(item.url)
      let id = String(item.url.deletingPathExtension().lastPathComponent.prefix(8))
      let estado =
        agora.timeIntervalSince(item.data) < 120 ? "trabalhando agora" : "parada desde \(hora.string(from: item.data))"
      let titulo =
        r.titulo ?? r.falas.first { $0.quem == "Gabriel" }.map { String($0.texto.prefix(80)) } ?? "sem título"
      let ultima = r.falas.last.map { "\n  último (\($0.quem)): \($0.texto.prefix(300))" } ?? ""
      return "id \(id) | \(titulo) | \(r.pasta ?? "?") | \(r.origem ?? "?") | \(estado)\(ultima)"
    }.joined(separator: "\n")
  }

  private static func ler(_ url: URL, n: Int) -> String {
    let r = resumo(url)
    let falas = r.falas.suffix(max(1, min(n, 40)))
    return "\(r.titulo ?? "sem título") | \(r.pasta ?? "?")\n"
      + falas.map { "\($0.quem): \($0.texto.prefix(1500))" }.joined(separator: "\n\n")
  }

  /// Abre `claude -p` na pasta, em segundo plano; a transcrição aparece no `listar` em segundos. Só pasta dentro da
  /// home, para o pedido não rodar em qualquer lugar do disco.
  private static func nova(pasta: String, texto: String) -> (Bool, String) {
    let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
    let dir = URL(fileURLWithPath: (pasta as NSString).expandingTildeInPath).standardizedFileURL
    var ehPasta: ObjCBool = false
    guard dir.path.hasPrefix(home + "/"), FileManager.default.fileExists(atPath: dir.path, isDirectory: &ehPasta),
      ehPasta.boolValue
    else { return (false, "A pasta precisa existir dentro de \(home).") }
    let pedido = texto.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !pedido.isEmpty else { return (false, "Falta o pedido da sessão.") }
    guard FileManager.default.isExecutableFile(atPath: claude) else {
      return (false, "Não achei o claude em \(claude).")
    }
    let logs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/JarvisSessoes")
    try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
    let saida = logs.appendingPathComponent("\(Int(Date().timeIntervalSince1970)).log")
    FileManager.default.createFile(atPath: saida.path, contents: nil)
    let p = Process()
    p.executableURL = URL(fileURLWithPath: claude)
    p.arguments = ["-p", pedido, "--permission-mode", "acceptEdits"]
    p.currentDirectoryURL = dir
    var env = ProcessInfo.processInfo.environment
    env["PATH"] = "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (env["PATH"] ?? "")
    p.environment = env
    if let h = try? FileHandle(forWritingTo: saida) {
      p.standardOutput = h
      p.standardError = h
    }
    do {
      try p.run()
    } catch {
      return (false, "Não consegui abrir a sessão: \(error.localizedDescription)")
    }
    log("Jarvis: sessão nova do Claude Code em \(dir.path) (pid \(p.processIdentifier))")
    return (true, "Sessão aberta em \(dir.path). Ela aparece no listar em segundos; a saída fica em \(saida.path).")
  }
}
