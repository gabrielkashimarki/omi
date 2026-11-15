import Foundation

/// Fork: mostra o diário do vault Obsidian (`06-Diario/AAAA-MM-DD.md`) na tela de resumo do dia.
///
/// A nota do vault é a fonte; o app só lê, a cada refresh do `HomeDailySummaryStore`, então uma
/// edição feita no Obsidian aparece no próximo refresh. Para o mesmo dia, a nota substitui o
/// resumo da nuvem e herda dele só os números (`stats`).
enum DiarioVault {
  static let pasta = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("obsidian/segundo-cerebro/06-Diario", isDirectory: true)

  private static let emojis = [
    "Reuniões": "🗓️", "Conversas": "💬", "Capturado por mim": "📝", "Foco": "🎯", "Omi": "🎙️",
  ]

  /// Junta nuvem e vault por data (o vault ganha) e devolve do mais novo para o mais antigo.
  static func mesclar(nuvem: [DailySummaryRecord], limite: Int, pasta: URL = pasta) -> [DailySummaryRecord] {
    var porData: [String: DailySummaryRecord] = [:]
    for r in nuvem { if let d = r.date { porData[d] = r } }
    for (data, url) in notas(em: pasta).prefix(limite) {
      guard let texto = try? String(contentsOf: url, encoding: .utf8),
        let r = registro(data: data, markdown: texto, stats: porData[data]?.stats)
      else { continue }
      porData[data] = r
    }
    return porData.values.sorted { ($0.date ?? "") > ($1.date ?? "") }.prefix(limite).map { $0 }
  }

  /// `(data, url)` das notas `AAAA-MM-DD.md`, mais novas primeiro.
  static func notas(em pasta: URL) -> [(String, URL)] {
    let nomes = (try? FileManager.default.contentsOfDirectory(atPath: pasta.path)) ?? []
    return nomes.compactMap { nome -> (String, URL)? in
      guard nome.hasSuffix(".md") else { return nil }
      let data = String(nome.dropLast(3))
      guard data.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
      return (data, pasta.appendingPathComponent(nome))
    }.sorted { $0.0 > $1.0 }
  }

  /// Seções `##` viram destaques; "Em uma linha" vira manchete e visão geral; "Pontas soltas"
  /// vira perguntas em aberto; linhas `- [ ]`/`- [x]` de qualquer seção viram tarefas.
  static func registro(data: String, markdown: String, stats: DailySummaryRecord.Stats? = nil) -> DailySummaryRecord? {
    var secoes: [(titulo: String, linhas: [String])] = []
    var tarefas: [DailySummaryRecord.ActionItem] = []
    var noFrontmatter = false
    for (i, bruta) in markdown.components(separatedBy: "\n").enumerated() {
      let linha = bruta.trimmingCharacters(in: .whitespaces)
      if linha == "---" && (i == 0 || noFrontmatter) { noFrontmatter.toggle(); continue }
      if noFrontmatter || linha.hasPrefix("<!--") || linha.hasPrefix("# ") { continue }
      if linha.hasPrefix("## ") {
        secoes.append((String(linha.dropFirst(3)), []))
      } else if let tarefa = tarefa(linha) {
        tarefas.append(tarefa)
      } else if !secoes.isEmpty, !linha.isEmpty {
        secoes[secoes.count - 1].linhas.append(limpar(linha))
      }
    }
    let resumo = secoes.first { $0.titulo == "Em uma linha" }?.linhas.joined(separator: " ")
    let pontas = secoes.first { $0.titulo == "Pontas soltas" }?.linhas ?? []
    let destaques = secoes
      .filter { !["Em uma linha", "Pontas soltas"].contains($0.titulo) && !$0.linhas.isEmpty }
      .map {
        DailySummaryRecord.Highlight(
          topic: $0.titulo, emoji: emojis[$0.titulo] ?? "📌", summary: $0.linhas.joined(separator: "\n"))
      }
    guard resumo != nil || !destaques.isEmpty || !tarefas.isEmpty else { return nil }
    return DailySummaryRecord(
      id: "vault:\(data)", date: data, headline: resumo.map(manchete), overview: resumo, dayEmoji: "📓",
      stats: stats, highlights: destaques, actionItems: tarefas,
      unresolvedQuestions: pontas.map {
        DailySummaryRecord.UnresolvedQuestion(question: $0.hasPrefix("• ") ? String($0.dropFirst(2)) : $0, conversationId: nil)
      })
  }

  private static func tarefa(_ linha: String) -> DailySummaryRecord.ActionItem? {
    for (marca, feita) in [("- [ ] ", false), ("- [x] ", true), ("- [X] ", true)] where linha.hasPrefix(marca) {
      return .init(description: limpar(String(linha.dropFirst(marca.count))), completed: feita)
    }
    return nil
  }

  /// Markdown mínimo para texto corrido: tira ênfase, código, links de wiki e troca "- " por "• ".
  static func limpar(_ linha: String) -> String {
    var s = linha.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
    s = s.replacingOccurrences(of: #"\[\[(?:[^\]|]*\|)?([^\]]*)\]\]"#, with: "$1", options: .regularExpression)
    if s.hasPrefix("- ") || s.hasPrefix("* ") { s = "• " + s.dropFirst(2) }
    if s.hasPrefix("### ") { s = String(s.dropFirst(4)) + ":" }
    return s
  }

  /// Primeira frase, até ~110 caracteres.
  private static func manchete(_ texto: String) -> String {
    let frase = texto.components(separatedBy: ". ").first ?? texto
    return frase.count > 110 ? String(frase.prefix(107)) + "..." : frase
  }
}
