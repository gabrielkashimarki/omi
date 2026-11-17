import Foundation

/// Cliente do cérebro do Jarvis no Fly (`smarten-agents/jarvis/cerebro.py`).
/// `POST /jarvis` devolve NDJSON: `{passo}`, `{confirmar:{id,resumo,fala}}` e, no fim, `{fala, detalhe_md}`.
/// A chave fica no cofre de segredos do app (Keychain, ou o arquivo do fork sem Team ID).
enum JarvisCliente {
  static let base = URL(string: "https://smarten-jarvis.fly.dev")!
  static let keyService = "com.omi.desktop.jarvis"
  static let keyAccount = "chave"

  static var chave: String? { DesktopKeychainStore.string(service: keyService, account: keyAccount) }

  enum Evento: Equatable, Sendable {
    case passo(String)
    case confirmar(id: String, resumo: String, fala: String)
    case fim(fala: String, detalhe: String)
  }

  struct Mensagem: Equatable, Sendable {
    let papel: String  // gabriel, jarvis, ferramenta, confirmacao
    let texto: String
    let detalhe: String
    let quando: Date?
  }

  enum Falha: Error {
    case semChave
    case http(Int)
  }

  // MARK: - Leitura (puro, testado)

  static func ler(_ linha: String) -> Evento? {
    guard let dados = linha.data(using: .utf8),
      let j = try? JSONSerialization.jsonObject(with: dados) as? [String: Any]
    else { return nil }
    if let c = j["confirmar"] as? [String: Any], let id = c["id"] as? String {
      return .confirmar(id: id, resumo: c["resumo"] as? String ?? "", fala: c["fala"] as? String ?? "")
    }
    if let fala = j["fala"] as? String {
      return .fim(fala: fala, detalhe: j["detalhe_md"] as? String ?? "")
    }
    if let passo = j["passo"] as? String { return .passo(passo) }
    return nil
  }

  /// Linhas de `GET /jarvis/historico`; o que é de ferramenta fica de fora do painel.
  static func historico(de dados: Data) -> [Mensagem] {
    let linhas = (try? JSONSerialization.jsonObject(with: dados) as? [[String: Any]]) ?? []
    return linhas.compactMap { m in
      guard let papel = m["papel"] as? String, papel != "ferramenta", let texto = m["texto"] as? String else {
        return nil
      }
      let detalhe = (m["extra"] as? [String: Any])?["detalhe_md"] as? String ?? ""
      return Mensagem(
        papel: papel, texto: texto, detalhe: detalhe,
        quando: (m["criado_em"] as? String).flatMap(MeetingCopilotServer.date))
    }
  }

  /// "mcp__jarvis__listar_demandas" vira "listar demandas"; o nome cru não diz nada na legenda.
  static func passoLegivel(_ ferramenta: String) -> String {
    let nome = ferramenta.split(separator: "__").last.map(String.init) ?? ferramenta
    switch nome {
    case "buscar_contexto": return "buscando no Cérebro"
    case "registrar": return "registrando no Cérebro"
    case "listar_demandas": return "olhando as demandas"
    case "criar_demanda": return "criando a demanda"
    case "concluir_demanda": return "concluindo a demanda"
    case "whatsapp_enviar": return "mandando WhatsApp"
    case "mexer_no_mac": return "mexendo no Mac"
    case "Bash": return "rodando no terminal"
    case "WebSearch", "WebFetch": return "procurando na web"
    default:
      return nome.hasPrefix("COMPOSIO")
        ? "consultando Gmail, Agenda ou Drive" : nome.replacingOccurrences(of: "_", with: " ")
    }
  }

  // MARK: - Rede

  static func requisicao(_ caminho: String, metodo: String = "GET", corpo: [String: Any]? = nil) throws -> URLRequest {
    guard let chave else { throw Falha.semChave }
    var r = URLRequest(url: URL(string: caminho, relativeTo: base)!)
    r.httpMethod = metodo
    // a máquina do Fly dorme: a primeira chamada paga a subida
    r.timeoutInterval = 120
    r.setValue("Bearer \(chave)", forHTTPHeaderField: "Authorization")
    if let corpo {
      r.setValue("application/json", forHTTPHeaderField: "Content-Type")
      r.httpBody = try JSONSerialization.data(withJSONObject: corpo)
    }
    return r
  }

  /// Manda o pedido e entrega cada evento do NDJSON na hora em que chega.
  static func pedir(_ texto: String, evento: @escaping @Sendable (Evento) async -> Void) async throws {
    let r = try requisicao("/jarvis", metodo: "POST", corpo: ["texto": texto, "origem": "mac"])
    let (bytes, resposta) = try await URLSession.shared.bytes(for: r)
    let status = (resposta as? HTTPURLResponse)?.statusCode ?? 0
    guard status == 200 else { throw Falha.http(status) }
    for try await linha in bytes.lines {
      guard let e = ler(linha) else { continue }
      await evento(e)
      if case .fim = e { return }
    }
  }

  static func confirmar(_ id: String, sim: Bool) async throws {
    let r = try requisicao("/jarvis/confirmacao", metodo: "POST", corpo: ["id": id, "resposta": sim ? "sim" : "nao"])
    let (_, resposta) = try await URLSession.shared.data(for: r)
    let status = (resposta as? HTTPURLResponse)?.statusCode ?? 0
    guard status == 200 else { throw Falha.http(status) }
  }

  /// Chamada JSON simples às rotas das abas (`/jarvis/tarefas`, `/jarvis/cerebro`): devolve o corpo da resposta.
  /// `corpo` vai já em JSON: `[String: Any]` não atravessa a fronteira de concorrência a partir da tela.
  static func dados(_ caminho: String, metodo: String = "GET", corpo: Data? = nil) async throws -> Data {
    var r = try requisicao(caminho, metodo: metodo)
    if let corpo {
      r.setValue("application/json", forHTTPHeaderField: "Content-Type")
      r.httpBody = corpo
    }
    let (dados, resposta) = try await URLSession.shared.data(for: r)
    let status = (resposta as? HTTPURLResponse)?.statusCode ?? 0
    guard status == 200 else { throw Falha.http(status) }
    return dados
  }

  static func json(_ corpo: [String: Any]) -> Data? { try? JSONSerialization.data(withJSONObject: corpo) }

  static func historico(horas: Int = 24) async throws -> [Mensagem] {
    let (dados, resposta) = try await URLSession.shared.data(for: try requisicao("/jarvis/historico?horas=\(horas)"))
    let status = (resposta as? HTTPURLResponse)?.statusCode ?? 0
    guard status == 200 else { throw Falha.http(status) }
    return historico(de: dados)
  }
}
