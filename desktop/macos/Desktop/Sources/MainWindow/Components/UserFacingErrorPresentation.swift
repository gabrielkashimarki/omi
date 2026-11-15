import Foundation

/// Maps transport and system failures into concise copy for non-chat UI.
///
/// Chat and agent transcripts deliberately keep their richer error context. This
/// mapper is only for app chrome outside active chat and agent transcripts, such
/// as dashboards, pages, sheets, and alerts, where a raw server detail or
/// decoding failure is distracting and unhelpful.
enum UserFacingErrorPresentation {
  enum Context {
    case dashboard
    case chatSessions
    case conversations
    case conversationSearch
    case conversationMerge
    case tasks
    case memories
    case memoryVisibility
    case memoryDeletion
    case screenshots
    case goals
    case persona
    case signIn
    case onboarding
    case integration(String)
    case browserExtension
    case memoryExport
    case storageSync
    case transcription
    case accountDeletion

    fileprivate var action: String {
      switch self {
      case .dashboard: return "atualizar o painel"
      case .chatSessions: return "carregar os chats"
      case .conversations: return "carregar as conversas"
      case .conversationSearch: return "buscar conversas"
      case .conversationMerge: return "mesclar conversas"
      case .tasks: return "atualizar as tarefas"
      case .memories: return "carregar as memórias"
      case .memoryVisibility: return "atualizar a visibilidade da memória"
      case .memoryDeletion: return "apagar as memórias"
      case .screenshots: return "carregar as capturas de tela"
      case .goals: return "carregar as metas"
      case .persona: return "carregar a sua persona"
      case .signIn: return "entrar"
      case .onboarding: return "salvar essa etapa"
      case .integration(let name): return "conectar ao \(name)"
      case .browserExtension: return "conectar a extensão do navegador"
      case .memoryExport: return "preparar essa exportação"
      case .storageSync: return "sincronizar o armazenamento do dispositivo"
      case .transcription: return "iniciar a transcrição"
      case .accountDeletion: return "apagar a sua conta"
      }
    }

    fileprivate var isSignIn: Bool {
      if case .signIn = self { return true }
      return false
    }
  }

  static func message(for error: Error, while context: Context) -> String {
    if let apiError = error as? APIError {
      switch apiError {
      case .httpError(let statusCode, _):
        switch statusCode {
        case 401:
          return context.isSignIn
            ? "Não foi possível entrar. Tente de novo."
            : "Entre de novo e tente mais uma vez."
        case 403:
          return "Você não tem permissão para fazer isso."
        case 409:
          return "Isto mudou enquanto o Omi atualizava. Atualize e tente de novo."
        case 429:
          return "O Omi está ocupado agora. Tente de novo em instantes."
        case 500...599:
          return "O serviço do Omi está indisponível agora. Tente de novo."
        default:
          return fallback(for: context)
        }
      case .invalidResponse, .decodingError:
        return "O Omi recebeu uma resposta inesperada. Tente de novo."
      case .memoryDeleteGateBusy:
        if case .memoryDeletion = context {
          return "A exclusão está atrasada enquanto o Omi conclui outra tarefa da conta. Ela será tentada de novo automaticamente."
        }
        return "O Omi está ocupado agora. Tente de novo em instantes."
      case .syncRateLimited:
        return "O Omi está ocupado agora. Tente de novo em instantes."
      case .unsupportedTierScopedBulkMutation:
        return "Essa opção ainda não está disponível."
      case .syncUploadRejected, .accountCutoverOfflineQueueBlocked:
        return fallback(for: context)
      case .unauthorized:
        return context.isSignIn
          ? "Não foi possível entrar. Tente de novo."
          : "Entre de novo e tente mais uma vez."
      }
    }

    if let urlError = error as? URLError {
      switch urlError.code {
      case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .networkConnectionLost,
        .notConnectedToInternet, .timedOut:
        return "Verifique sua conexão e tente de novo."
      default:
        return fallback(for: context)
      }
    }

    return fallback(for: context)
  }

  /// Sanitizes already-materialized error copy at display time when the original
  /// `Error` is not available (for example, values stored on invariant-owned types).
  static func message(from raw: String, while context: Context) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return fallback(for: context) }
    if shouldPreserveCuratedCopy(trimmed) {
      return trimmed
    }
    return fallback(for: context)
  }

  /// Raw-system-error fingerprints. Copy that carries none of them is copy this
  /// app wrote, and is shown verbatim.
  ///
  /// This deliberately does not judge by sentence shape. A previous version also
  /// required a trailing period and fewer than 120 characters, which flattened
  /// five real connector messages into the generic fallback — including the
  /// Calendar not-signed-in guidance, at exactly 120 characters, which is the
  /// single most common Google connect failure and the one that most needs its
  /// next step shown. Length and punctuation do not separate curated copy from
  /// raw system text; the fingerprints below do.
  private static func shouldPreserveCuratedCopy(_ text: String) -> Bool {
    let lowered = text.lowercased()
    if text.count > 160 { return false }
    if text.contains("://") { return false }
    // Catches `Error Domain=` and every bare `NS*ErrorDomain` spelling.
    if lowered.contains("errordomain") { return false }
    if lowered.contains("cfstream") { return false }
    if lowered.range(of: #"\b[45]\d{2}\b"#, options: .regularExpression) != nil { return false }
    if text.filter({ $0 == ":" }).count > 1 { return false }
    return true
  }

  private static func fallback(for context: Context) -> String {
    "Não foi possível \(context.action). Tente de novo."
  }
}
