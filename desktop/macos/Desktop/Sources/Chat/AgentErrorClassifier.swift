import Foundation

/// Bounded classification for free-form agent error strings.
///
/// PostHog telemetry may only carry bounded dimensions (never raw exception
/// text), and users may only be told "try again" when retrying can actually
/// help. This classifier is the single source for both: the 30-day
/// `chat_agent_error` corpus showed the opaque "Something went wrong. Please
/// try again." bucket was dominated by unretryable causes (exhausted provider
/// credits alone produced retry storms of 30+ events/day from single users).
enum AgentErrorCode: String, CaseIterable, Sendable {
  case providerBillingExhausted = "provider_billing_exhausted"
  case providerAuthExpired = "provider_auth_expired"
  case oauthTimeout = "oauth_timeout"
  case connectionFailed = "connection_failed"
  case payloadTooLarge = "payload_too_large"
  case runtimeCrashed = "runtime_crashed"
  case runtimeInstallIncomplete = "runtime_install_incomplete"
  case toolSchemaRejected = "tool_schema_rejected"
  case providerRateLimited = "provider_rate_limited"
  case providerOverloaded = "provider_overloaded"
  case localDataError = "local_data_error"
  case credentialLeakSuspected = "credential_leak_suspected"
  case planLimitReached = "plan_limit_reached"
  case agentModeUnavailable = "agent_mode_unavailable"
  case upstreamProviderFailed = "upstream_provider_failed"
  case userInterrupted = "user_interrupted"
  case unknown
}

struct ClassifiedAgentError: Equatable, Sendable {
  let code: AgentErrorCode
  let userMessage: String
  let retryable: Bool
}

enum AgentErrorClassifier {
  /// Single copy for an install whose agent runtime payload is incomplete.
  /// Owned here because this classifier is also the round-trip target: surfaces
  /// re-classify already-classified messages, so the phrase in the copy has to
  /// be the same phrase the rule matches.
  static let runtimeInstallIncompleteMessage =
    "O runtime local de IA do Omi não está instalado corretamente, então o chat não consegue iniciar. "
    + "Reinstale ou atualize o Omi para corrigir."

  /// A transport status identifies a billing rejection, not whose account
  /// paid for the request. BYOK and managed requests can share the same proxy.
  static let billingFailureMessage =
    "O serviço de IA recusou esta solicitação por motivos de cobrança. "
    + "Confira seu provedor e sua chave de API em Ajustes → IA e Automação. "
    + "Se estiverem corretos, fale com o suporte do Omi. Reenviar a mesma mensagem não vai resolver."

  /// Worker recycle rewrites `userMessage` to "send again" while leaving the
  /// provider's 402 on `technicalMessage`. Classify both or the billing rule
  /// never fires and the transcript falls through to the unclassified marker.
  static func classify(_ failure: AgentRuntimeFailure) -> ClassifiedAgentError {
    classify(
      [failure.technicalMessage, failure.userMessage]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    )
  }

  // ponytail: ordered substring rules over the observed error corpus; a rule
  // table beats ML until the corpus outgrows it. First match wins.
  static func classify(_ rawMessage: String) -> ClassifiedAgentError {
    let lower = rawMessage.lowercased()

    // User pressed Stop — not a technical failure. Recognized so it is never
    // mislabeled as a retryable error (the #1 string in the live corpus, 616
    // events/30d); upstream telemetry should also split it from chat_agent_error.
    if lower.hasPrefix("response stopped") || lower.hasPrefix("resposta interrompida") {
      return ClassifiedAgentError(
        code: .userInterrupted,
        userMessage: "Resposta interrompida.",
        retryable: false)
    }
    // Surfaces classify displayed copy again. Recognize both the current
    // sentence and the old managed-lane wording before its "Plan and Usage"
    // advice can turn a billing rejection into a plan-limit diagnosis.
    if lower.contains("declined this request for billing reasons")
      || lower.contains("recusou esta solicitação por motivos de cobrança")
    {
      return ClassifiedAgentError(
        code: .providerBillingExhausted,
        userMessage: billingFailureMessage,
        retryable: false)
    }
    // Plan/usage cap — retrying just re-hits the cap (measured retry storms in
    // the live corpus). Direct to upgrade/reset, never "try again".
    if lower.contains("free plan limit") || lower.contains("plan and usage")
      || (lower.contains("plan limit") && lower.contains("upgrade"))
      || lower.contains("limite de chat do seu plano")
    {
      return ClassifiedAgentError(
        code: .planLimitReached,
        userMessage:
          "Você atingiu o limite de chat do seu plano. Faça upgrade em Ajustes → Plano e Uso, ou aguarde o próximo reinício.",
        retryable: false)
    }
    // Provider/mode configuration mismatch — retrying the same query cannot
    // help; the user must change the agent mode/provider in Settings.
    if lower.contains("only when the user claude mode")
      || lower.contains("can only use omi cloud routing")
      || lower.contains("provider mode is pinned")
      || (lower.contains("is not available") && lower.contains("make sure"))
      || lower.contains("agente não está disponível na sua configuração atual")
    {
      return ClassifiedAgentError(
        code: .agentModeUnavailable,
        userMessage:
          "Este agente não está disponível na sua configuração atual. Abra os Ajustes, confira o modo/provedor do agente e tente de novo.",
        retryable: false)
    }

    // A bundle that shipped without its agent runtime payload fails identically
    // on every turn, so "the AI engine restarted, try again" is the wrong copy —
    // that phrasing produced retry loops against a permanently broken install.
    // Matched before the generic "process exited" rule below, which pi-mono's
    // own rejection string (`pi-mono process exited (code 1)`) would otherwise
    // claim. Also recognizes this classifier's own output so surfaces that
    // re-classify an already-classified message stay on the same code.
    if lower.contains("local ai runtime is not installed correctly")
      || lower.contains("runtime local de ia do omi não está instalado corretamente")
      || lower.contains("extension path does not exist")
      || lower.contains("failed to load extension")
      || (lower.contains("unknown provider") && lower.contains("omi"))
    {
      return ClassifiedAgentError(
        code: .runtimeInstallIncomplete,
        userMessage: runtimeInstallIncompleteMessage,
        retryable: false)
    }

    // Omi's own desktop chat backend reports every upstream failure as the
    // fixed string "Upstream provider error" with code 502, delivered as an SSE
    // error frame inside an HTTP 200 body. The corpus had no rule for it, so it
    // fell through to `unknown` and the transcript showed the generic "Omi
    // couldn't answer this one" — which is what users saw for ~19 hours during
    // the 2026-08-20 gateway-parameter outage, with nothing on screen
    // indicating the failure was ours rather than their message.
    //
    // Retryable: the backend emits this for transient gateway conditions
    // (circuit open, transport failure, upstream timeout) as well as hard
    // rejections, and it does not distinguish them on the wire. Resending is
    // worth one attempt.
    //
    // Desktop-backend also answers a coded 503 with an empty body
    // (`HTTP 503 status code (no body)`). That string never contains
    // "Upstream provider error", so without a status-shaped rule it fell
    // through to `unknown` and the generic "Omi couldn't answer this one".
    if lower.contains("upstream provider error")
      || lower.range(of: #"\bhttp[\s/]*503\b"#, options: .regularExpression) != nil
      || lower.range(
        of: #"\b(?:503\s+status|status(?:\s+code)?\s*[:=]?\s*503)\b"#,
        options: .regularExpression) != nil
    {
      return ClassifiedAgentError(
        code: .upstreamProviderFailed,
        userMessage:
          "O serviço de IA do Omi não respondeu. O problema é do nosso lado, não da sua mensagem. "
          + "Tente de novo em instantes.",
        retryable: true)
    }

    // The desktop proxy answers an exhausted billing lane with a bare 402
    // and no body, so the raw transport string ("HTTP 402 status code (no
    // body)") fell through to `unknown` and was shown verbatim — and, worse,
    // marked retryable, which is the retry storm this classifier exists to
    // prevent. Payment Required is never fixed by resending the same message.
    // Matched on status shape rather than a bare `402` so a token count or cost
    // that happens to contain those digits cannot claim this rule.
    if lower.contains("payment required")
      || lower.range(of: #"\bhttp[\s/]*402\b"#, options: .regularExpression) != nil
      || lower.range(
        of: #"\b(?:402\s+status|status(?:\s+code)?\s*[:=]?\s*402)\b"#,
        options: .regularExpression) != nil
    {
      return ClassifiedAgentError(
        code: .providerBillingExhausted,
        userMessage: billingFailureMessage,
        retryable: false)
    }
    if lower.contains("credit balance is too low") {
      return ClassifiedAgentError(
        code: .providerBillingExhausted,
        userMessage: billingFailureMessage,
        retryable: false)
    }
    if lower.contains("oauth callback timed out") || lower.contains("tempo esgotado no login") {
      return ClassifiedAgentError(
        code: .oauthTimeout,
        userMessage: "Tempo esgotado no login. Abra os Ajustes e reconecte sua conta.",
        retryable: false)
    }
    // Only high-signal leak tokens belong here — providers say "leaked",
    // "invalid key", or "has been disabled" when a key is compromised. Generic
    // "forbidden"/"permission denied" are ordinary 403 authorization failures,
    // not leaks; classing them here both mislabels the user copy and gets the
    // event class already classified as expected ("ai service
    // authentication error"), hiding real forbidden-class bugs from triage.
    if lower.contains("leaked") || lower.contains("invalid key") || lower.contains("has been disabled")
      || lower.contains("erro de autenticação do serviço de ia")
    {
      return ClassifiedAgentError(
        code: .credentialLeakSuspected,
        userMessage: "Erro de autenticação do serviço de IA. Atualize o app para a versão mais recente.",
        retryable: false)
    }
    if lower.contains("invalid_token") || lower.contains("authentication_error")
      || lower.contains("failed to authenticate") || lower.contains("unauthorized")
      || lower.contains("authentication required") || lower.contains("byok_validation_failed")
      || lower.contains("forbidden") || lower.contains("permission denied")
      || lower.contains("api key") || lower.contains("api_key")
      || lower.contains("sua sessão de ia expirou")
    {
      return ClassifiedAgentError(
        code: .providerAuthExpired,
        userMessage: "Sua sessão de IA expirou. Reconecte sua conta nos Ajustes e tente de novo.",
        retryable: false)
    }
    if lower.contains("connection error") || lower.contains("econnrefused") || lower.contains("etimedout")
      || lower.contains("socket hang up") || lower.contains("network is unreachable")
    {
      return ClassifiedAgentError(
        code: .connectionFailed,
        userMessage: "Não foi possível acessar o serviço de IA. Confira sua conexão com a internet e tente de novo.",
        retryable: true)
    }
    if lower.contains("length limit exceeded") || lower.contains("payload too large")
      || lower.range(of: #"\b413\b"#, options: .regularExpression) != nil
      || lower.contains("grandes demais para enviar")
    {
      return ClassifiedAgentError(
        code: .payloadTooLarge,
        userMessage:
          "Essa mensagem ou seus anexos são grandes demais para enviar. Tente um anexo menor ou uma mensagem mais curta.",
        retryable: false)
    }
    if lower.contains("process exited") || lower.contains("process not running") || lower.contains("terminated") {
      return ClassifiedAgentError(
        code: .runtimeCrashed,
        userMessage: "O motor de IA reiniciou inesperadamente. Tente enviar a mensagem de novo.",
        retryable: true)
    }
    if lower.contains("input_schema does not support") || lower.contains("tool_choice")
      || lower.contains("tool names must be unique") || lower.contains("tools must have unique names")
      || lower.contains("uma ferramenta conectada está mal configurada")
    {
      return ClassifiedAgentError(
        code: .toolSchemaRejected,
        userMessage:
          "Uma ferramenta conectada está mal configurada. Isso não foi causado pela sua mensagem. Tentar de novo não vai ajudar até a ferramenta ser corrigida; o erro foi registrado.",
        retryable: false)
    }
    if lower.contains("rate limit") || lower.contains("quota") || lower.contains("resource exhausted")
      || lower.contains("429")
    {
      return ClassifiedAgentError(
        code: .providerRateLimited,
        userMessage: "O serviço de IA está ocupado. Tente de novo em instantes.",
        retryable: true)
    }
    if lower.contains("overloaded") || lower.contains("service unavailable")
      || lower.contains("temporarily unavailable") || lower.contains("internal error")
      || lower.contains("529")
    {
      return ClassifiedAgentError(
        code: .providerOverloaded,
        userMessage: "O serviço de IA está temporariamente indisponível. Tente de novo mais tarde.",
        retryable: true)
    }
    if lower.contains("transaction within a transaction") || lower.contains("database disk image")
      || lower.contains("database is locked") || lower.contains("no column named")
      || lower.contains("no such column") || lower.contains("no such table")
      || lower.contains("erro de dados locais")
    {
      return ClassifiedAgentError(
        code: .localDataError,
        userMessage: "O Omi encontrou um erro de dados locais. Reiniciar o app costuma resolver; seus dados estão seguros.",
        retryable: false)
    }

    // Unknown: keep the original message when it exists (many provider errors
    // are already user-readable); only truly empty errors get the generic copy.
    let fallback = rawMessage.isEmpty ? "Algo deu errado. Tente de novo." : rawMessage
    return ClassifiedAgentError(code: .unknown, userMessage: fallback, retryable: true)
  }
}
