//
//  AgentesEventos.swift — o que os hooks do Claude Code mandam, o quadro de sessões e a resposta
//  que volta para o Claude numa permissão.
//
//  Portado do Coucou (MIT, © 2026 Louis Raillé, aviso em THIRD_PARTY_COUCOU_LICENSE):
//  `NotchBuddy/Sources/App/HookServer.swift` (processEvent, processPermissionRequest,
//  sendApprovalDecision) e o relay `nb-hook.py` embutido nele (montagem do hookSpecificOutput).
//

import Foundation

/// Um evento de hook já lido, pronto para cruzar de thread.
struct EventoAgente: Equatable, Sendable {
  var nome: String
  var sessao: String
  var projeto: String
  var ferramenta: String?
  /// O comando, o arquivo, o prompt ou a mensagem, numa linha.
  var resumo: String?
  /// `permission_suggestions` do PermissionRequest, em JSON, para o "Sempre".
  var sugestoes: Data?

  static func ler(_ dados: Data) -> EventoAgente? {
    guard let payload = try? JSONSerialization.jsonObject(with: dados) as? [String: Any],
      let nome = payload["hook_event_name"] as? String, !nome.isEmpty
    else { return nil }
    let cwd = payload["cwd"] as? String ?? ""
    let titulo = (payload["session_title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    let pasta = cwd.isEmpty ? nil : URL(fileURLWithPath: cwd).lastPathComponent
    let entrada = payload["tool_input"] as? [String: Any] ?? [:]
    let resumo =
      (entrada["command"] ?? entrada["file_path"] ?? entrada["url"] ?? entrada["pattern"]
      ?? entrada["description"] ?? payload["prompt"] ?? payload["message"]) as? String
    var sugestoes: Data?
    if let lista = payload["permission_suggestions"] as? [Any], !lista.isEmpty {
      sugestoes = try? JSONSerialization.data(withJSONObject: lista)
    }
    return EventoAgente(
      nome: nome,
      sessao: payload["session_id"] as? String ?? "desconhecida",
      projeto: titulo ?? pasta ?? "Claude Code",
      ferramenta: payload["tool_name"] as? String,
      resumo: resumo.map { umaLinha($0) },
      sugestoes: sugestoes)
  }

  static func umaLinha(_ texto: String, limite: Int = 120) -> String {
    let linha = texto.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    let limpa = linha.trimmingCharacters(in: .whitespaces)
    return limpa.count > limite ? String(limpa.prefix(limite)) + "…" : limpa
  }
}

enum EstadoSessao: String, Equatable, Sendable {
  case parada, pensando, trabalhando, terminou, precisaDeVoce, erro

  var rotulo: String {
    switch self {
    case .parada: return "Parada"
    case .pensando: return "Pensando"
    case .trabalhando: return "Trabalhando"
    case .terminou: return "Terminou"
    case .precisaDeVoce: return "Precisa de você"
    case .erro: return "Erro"
    }
  }
}

struct SessaoAgente: Identifiable, Equatable, Sendable {
  let id: String
  var projeto: String
  var estado: EstadoSessao
  var passo: String
  var atualizada: Date
}

/// As sessões ao vivo, atualizadas evento a evento.
struct QuadroAgentes: Equatable, Sendable {
  var sessoes: [String: SessaoAgente] = [:]

  /// As sessões da mais recente para a mais antiga.
  var lista: [SessaoAgente] { sessoes.values.sorted { $0.atualizada > $1.atualizada } }

  mutating func aplicar(_ e: EventoAgente, agora: Date = Date()) {
    if e.nome == "SessionEnd" {
      sessoes[e.sessao] = nil
      return
    }
    var s =
      sessoes[e.sessao]
      ?? SessaoAgente(id: e.sessao, projeto: e.projeto, estado: .parada, passo: "", atualizada: agora)
    s.projeto = e.projeto
    s.atualizada = agora
    switch e.nome {
    case "SessionStart":
      s.estado = .parada
    case "UserPromptSubmit":
      s.estado = .pensando
      s.passo = e.resumo ?? ""
    case "PreToolUse":
      s.estado = .trabalhando
      s.passo = [e.ferramenta, e.resumo].compactMap { $0 }.joined(separator: ": ")
    case "PostToolUse", "PostToolUseFailure", "SubagentStart", "SubagentStop":
      if s.estado != .precisaDeVoce { s.estado = .trabalhando }
    case "PermissionRequest":
      s.estado = .precisaDeVoce
      s.passo = [e.ferramenta, e.resumo].compactMap { $0 }.joined(separator: ": ")
    case "Notification":
      s.estado = .precisaDeVoce
      if let resumo = e.resumo { s.passo = resumo }
    case "Stop":
      s.estado = .terminou
    case "StopFailure":
      s.estado = .erro
    default:
      break
    }
    sessoes[e.sessao] = s
  }
}

/// A escolha no cartão de permissão.
enum DecisaoPermissao: String, Sendable {
  case permitir, negar, sempre

  /// O JSON que o hook imprime para o Claude Code. "Sempre" aplica as sugestões que o próprio
  /// Claude mandou (as mesmas do "não pergunte de novo" do terminal).
  func respostaClaude(sugestoes: Data?) -> String {
    var decisao: [String: Any]
    switch self {
    case .permitir:
      decisao = ["behavior": "allow"]
    case .sempre:
      decisao = ["behavior": "allow"]
      if let sugestoes, let lista = try? JSONSerialization.jsonObject(with: sugestoes) as? [Any] {
        decisao["updatedPermissions"] = lista
      }
    case .negar:
      decisao = ["behavior": "deny", "message": "Negado pelo Jarvis"]
    }
    let saida: [String: Any] = [
      "hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decisao]
    ]
    guard let dados = try? JSONSerialization.data(withJSONObject: saida, options: [.sortedKeys]) else {
      return ""
    }
    return String(decoding: dados, as: UTF8.self)
  }
}
