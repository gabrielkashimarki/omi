import Foundation

struct MemoryExportStatus: Sendable {
  let exportedCount: Int
  let lastExportedAt: Date?
  let detailText: String?
  let isConfigured: Bool
  let hasConnection: Bool
  /// Owned config block points at the legacy /v1/mcp/sse alias with the current
  /// key — a migration target that an Update action rewrites to /v1/mcp.
  let needsUpdate: Bool
}

struct MCPSetupCompletionSummary: Equatable, Sendable {
  let title: String
  let subtitle: String
}

struct MemoryExportConnectionPresentation: Equatable {
  let primaryActionTitle: String?
  let completion: MCPSetupCompletionSummary?

  static func make(
    destination: MemoryExportDestination,
    status: MemoryExportStatus?,
    isRunning: Bool,
    accessibilityPreflightMissing: Bool = false
  ) -> MemoryExportConnectionPresentation {
    if status?.hasConnection == true {
      return MemoryExportConnectionPresentation(
        primaryActionTitle: nil,
        completion: destination.mcpSetupCompletionSummary
      )
    }
    if status?.needsUpdate == true {
      return MemoryExportConnectionPresentation(primaryActionTitle: "Atualizar", completion: nil)
    }

    let title: String
    if isRunning {
      title = "Conectando…"
    } else {
      switch destination.mcpExecuteKind {
      case .directoryApp:
        title = "Adicionar o Omi ao ChatGPT"
      case .localAutonomous:
        title = "Faça por mim"
      case .browserAutonomous:
        title = accessibilityPreflightMissing ? "Conceder Acessibilidade" : "Faça por mim"
      case .assisted:
        title = destination.assistedOverlayHint != nil ? "Abrir e me guiar" : "Abrir e copiar chave"
      }
    }

    return MemoryExportConnectionPresentation(primaryActionTitle: title, completion: nil)
  }
}

/// Rendered MCP connection instructions for a single client.
struct MCPSetup: Sendable {
  let serverURL: String
  let copyTitle: String?
  let copyText: String?
  let steps: [String]
  let openURL: URL?
  let openTitle: String?
}

struct MemoryExportResult: Sendable {
  let memoryCount: Int
  let detailText: String?
  let destinationURL: URL?
  let fileURL: URL?
  let clipboardText: String?
}

struct AgentConnectionTestResult: Sendable {
  let hostedMemoryCount: Int

  var summary: String {
    "Conexão ok: o Omi devolveu \(hostedMemoryCount) memórias hospedadas."
  }
}

enum MemoryExportError: LocalizedError {
  case noMemories
  case invalidNotionConfiguration
  case invalidNotionResponse
  case invalidObsidianVault
  case requestFailed(String)

  var errorDescription: String? {
    switch self {
    case .noMemories:
      return "Ainda não há memórias disponíveis para exportar."
    case .invalidNotionConfiguration:
      return "Informe o token de integração do Notion e o ID da página pai."
    case .invalidNotionResponse:
      return "O Notion devolveu uma resposta inesperada."
    case .invalidObsidianVault:
      return "Escolha primeiro uma pasta de cofre do Obsidian válida."
    case .requestFailed(let message):
      return message
    }
  }
}
