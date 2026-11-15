import OmiTheme
import Sparkle
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// What a settled BYOK key set owes the backend.
///
/// The key fields are `SecureField`s bound straight to `@AppStorage`, so the
/// binding is written on *every character*. Reconciling on each of those writes
/// pinged provider auth endpoints with a half-typed key and flapped the
/// backend free-plan flag once per keystroke. Deciding the action from the
/// settled key set — separately from performing it — is what makes that policy
/// testable without a network.
enum BYOKReconciliation {
  enum Action: Equatable {
    /// Every key is present: prove them against the providers, then flip the
    /// free plan on (or back off if a provider rejects one).
    case validateAndActivate
    /// The free plan cannot be active with a partial key set.
    case deactivate
    /// Nothing was ever entered and nothing was ever reconciled — opening the
    /// pane is not a reason to touch the network.
    case none
  }

  static func action(
    forKeys keys: [String],
    hasCheckedStatuses: Bool,
    hasActivationError: Bool
  ) -> Action {
    let entered = keys.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    if entered.count == keys.count, !keys.isEmpty { return .validateAndActivate }
    if entered.isEmpty, !hasCheckedStatuses, !hasActivationError { return .none }
    return .deactivate
  }
}

extension SettingsContentView {
  var developerKeysSubsection: some View {
    VStack(spacing: OmiSpacing.xl) {
      byokStatusBanner

      settingsCard(settingId: "advanced.devkeys.llm") {
        VStack(alignment: .leading, spacing: OmiSpacing.sm) {
          Text("Modelo de linguagem")
            .scaledFont(size: OmiType.body, weight: .medium)
            .foregroundColor(Ink.primary)
          Text("Escolha um provedor para os recursos compatíveis de memórias e insights. O chat do desktop aceita chaves da Anthropic.")
            .scaledFont(size: OmiType.caption)
            .foregroundColor(Ink.secondary)
          Picker("Provedor de LLM", selection: $devBYOKLLMProvider) {
            ForEach(BYOKLLMProvider.allCases) { provider in
              Text(provider.displayName).tag(provider.rawValue)
            }
          }
          .pickerStyle(.menu)
        }
      }

      developerKeyField(
        provider: selectedBYOKLLMProvider.provider,
        title: "Chave de API: \(selectedBYOKLLMProvider.displayName)",
        subtitle: selectedBYOKLLMSubtitle,
        settingId: "advanced.devkeys.llm-key",
        value: selectedBYOKLLMKey
      )

      developerKeyField(
        provider: .deepgram,
        title: "Chave de API do Deepgram",
        subtitle: "Necessária para usar sua própria chave do Deepgram. Sem ela, a transcrição conta no seu plano Omi.",
        settingId: "advanced.devkeys.deepgram",
        value: $devDeepgramKey
      )

      if let byokActivationError {
        byokWarningCard(byokActivationError, settingId: "advanced.devkeys.error")
      }

      if hasAnyBYOKKey {
        settingsCard(settingId: "advanced.devkeys.clear") {
          HStack {
            Spacer()
            Button(action: clearAllBYOKKeys) {
              Text("Limpar Todas as Chaves Próprias")
                .scaledFont(size: OmiType.body, weight: .medium)
                .foregroundColor(Ink.errorRed)
            }
            .buttonStyle(.plain)
            Spacer()
          }
        }
      }
    }
    // One reconcile per settled key set, not one per keystroke. `.task(id:)`
    // cancels the superseded run, so a key typed by hand reaches the providers
    // once — and opening the pane with four saved keys finally fills in the
    // per-provider badges instead of leaving them blank until the next edit.
    .task(id: byokKeySetFingerprint) {
      migrateLegacyBYOKSelection()
      await refreshBYOKActivation()
    }
  }

  /// Identity of the current key set for `.task(id:)` — a SHA-256 over the four
  /// values, never the values themselves, so the view can compare key sets
  /// without a secret sitting in a view-diff identity.
  var byokKeySetFingerprint: String {
    APIKeyService.byokFingerprint(
      [devBYOKLLMProvider, selectedBYOKLLMKey.wrappedValue, devDeepgramKey].joined(separator: "\u{1}"))
  }

  var selectedBYOKLLMProvider: BYOKLLMProvider {
    BYOKLLMProvider(rawValue: devBYOKLLMProvider)
      ?? APIKeyService.selectedBYOKLLMProvider.flatMap { BYOKLLMProvider(rawValue: $0.rawValue) }
      ?? .openrouter
  }

  func migrateLegacyBYOKSelection() {
    guard BYOKLLMProvider(rawValue: devBYOKLLMProvider) == nil else { return }
    devBYOKLLMProvider = selectedBYOKLLMProvider.rawValue
  }

  var selectedBYOKLLMKey: Binding<String> {
    switch selectedBYOKLLMProvider {
    case .openrouter: return $devOpenRouterKey
    case .openai: return $devOpenAIKey
    case .gemini: return $devGeminiKey
    case .anthropic: return $devAnthropicKey
    }
  }

  var selectedBYOKLLMSubtitle: String {
    switch selectedBYOKLLMProvider {
    case .openrouter: return "Encaminha os modelos compatíveis pela sua conta do OpenRouter."
    case .openai: return "Usa sua chave de API da OpenAI diretamente."
    case .gemini: return "Usa o Gemini 2.5 Flash Lite diretamente."
    case .anthropic: return "Usa sua chave de API da Anthropic diretamente."
    }
  }

  func byokWarningCard(_ text: String, settingId: String) -> some View {
    settingsCard(settingId: settingId) {
      HStack(spacing: OmiSpacing.sm) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundColor(SettingsInk.notice)
        Text(text)
          .scaledFont(size: OmiType.caption)
          .foregroundColor(SettingsInk.notice)
      }
    }
  }

  var hasAnyBYOKKey: Bool {
    !devOpenRouterKey.isEmpty || !devOpenAIKey.isEmpty || !devAnthropicKey.isEmpty || !devGeminiKey.isEmpty
      || !devDeepgramKey.isEmpty
  }

  var hasActiveLLMByok: Bool {
    APIKeyService.isByokActive
  }

  var byokStatusTitle: String {
    hasActiveLLMByok ? "BYOK de LLM ativa" : "Use suas próprias chaves"
  }

  var byokUsageDescription: String {
    "Uma chave de LLM cobre só os recursos de IA compatíveis. O chat do desktop aceita chaves da Anthropic; outras chaves de LLM não removem o limite de chat do Omi."
  }

  @ViewBuilder
  var byokStatusBanner: some View {
    settingsCard(settingId: "advanced.devkeys.info") {
      HStack(alignment: .top, spacing: OmiSpacing.md) {
        Image(systemName: hasActiveLLMByok ? "checkmark.seal.fill" : "key.fill")
          .foregroundColor(hasActiveLLMByok ? Ink.listeningGreen : Ink.secondary)
        VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
          Text(byokStatusTitle)
            .scaledFont(size: OmiType.body, weight: .semibold)
            .foregroundColor(Ink.primary)
          Text(byokUsageDescription)
            .scaledFont(size: OmiType.caption)
            .foregroundColor(Ink.secondary)
          Text(
            "É preciso uma chave do Deepgram validada para não usar a franquia de transcrição do Omi. Sem ela, novas conversas sincronizadas podem ser bloqueadas quando essa franquia acabar."
          )
          .scaledFont(size: OmiType.caption)
          .foregroundColor(Ink.secondary)
          Text(TranscriptionAllowancePresentation.statusText(userSubscription?.transcriptionAllowance))
            .scaledFont(size: OmiType.caption, weight: .medium)
            .foregroundColor(Ink.primary)
          Text("Adicionar o Deepgram depois não desbloqueia conversas que já foram bloqueadas.")
            .scaledFont(size: OmiType.caption)
            .foregroundColor(Ink.secondary)
          Text("As chaves ficam salvas neste Mac e são enviadas nas requisições, nunca armazenadas nos servidores do Omi.")
            .scaledFont(size: OmiType.caption)
            .foregroundColor(Ink.secondary)
        }
        Spacer()
      }
    }
  }

  func clearAllBYOKKeys() {
    devOpenAIKey = ""
    devOpenRouterKey = ""
    devAnthropicKey = ""
    devGeminiKey = ""
    devDeepgramKey = ""
    byokKeyStatuses = [:]
    byokActivationError = nil
    // Clearing the fields is an explicit "take me off the free plan", so say so
    // now rather than leaving it to the debounced reconcile. Cleared within the
    // debounce window the reconcile sees an untouched-looking form and — quite
    // correctly — decides there is nothing to do, which would have left the
    // backend believing BYOK was still active with no keys behind it. Both
    // paths only ever deactivate, so the duplicate call is harmless.
    Task {
      try? await APIClient.shared.deactivateBYOK()
      APIKeyService.persistEnrolledFingerprints([:])
      await FloatingBarUsageLimiter.shared.fetchPlan()
    }
  }

  /// Debounce before a settled key set is spent on the network. Long enough to
  /// swallow hand-typing, short enough that a paste feels immediate.
  static let byokReconcileDebounce: Duration = .milliseconds(600)

  @MainActor
  func refreshBYOKActivation() async {
    guard !selectedBYOKLLMKey.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      byokKeyStatuses = [:]
      byokActivationError = nil
      if hasAnyBYOKKey || !APIKeyService.enrolledFingerprints().isEmpty {
        try? await APIClient.shared.deactivateBYOK()
        APIKeyService.persistEnrolledFingerprints([:])
        await FloatingBarUsageLimiter.shared.fetchPlan()
      }
      loadSubscriptionInfo()
      return
    }
    let action = BYOKReconciliation.action(
      forKeys: [selectedBYOKLLMKey.wrappedValue],
      hasCheckedStatuses: !byokKeyStatuses.isEmpty,
      hasActivationError: byokActivationError != nil
    )
    guard action != .none else { return }

    do {
      try await Task.sleep(for: Self.byokReconcileDebounce)
    } catch {
      return  // superseded by a newer key set
    }

    switch action {
    case .none:
      return

    case .validateAndActivate:
      let candidateSnapshot = APIKeyService.byokActivationCandidateSnapshot
      // The badge state the UI has always been able to draw but never reached:
      // say a provider is being checked while it is being checked.
      var checking: [BYOKProvider: BYOKValidator.Status] = [:]
      for provider in candidateSnapshot.keys { checking[provider] = .checking }
      byokKeyStatuses = checking

      // Validate before flipping the backend flag — otherwise we'd put the
      // user on the free plan with dead keys and every chat would 401.
      let snapshot = candidateSnapshot.reduce(into: [BYOKProvider: String]()) {
        acc, entry in acc[entry.key] = entry.value.key
      }
      let results = await BYOKValidator.validateAll(snapshot)
      guard !Task.isCancelled else { return }
      let selectedLLMValid =
        results[selectedBYOKLLMProvider.provider].map {
          if case .ok = $0 { return true }
          return false
        } ?? false
      if selectedLLMValid {
        let fingerprints = candidateSnapshot.reduce(into: [String: String]()) { acc, entry in
          if let status = results[entry.key], case .ok = status {
            acc[entry.key.rawValue] = entry.value.fingerprint
          }
        }
        do {
          try await APIClient.shared.activateBYOK(fingerprints: fingerprints)
          APIKeyService.persistEnrolledFingerprints(fingerprints)
          await FloatingBarUsageLimiter.shared.fetchPlan()
          await MainActor.run {
            // Clear any sticky paywall flag from a prior `freemium_threshold_reached`
            // event — once the selected LLM BYOK key validates, the user is on the
            // free BYOK plan for supported AI features. Managed transcription
            // still follows the server allowance without an enrolled Deepgram key.
            AppState.current?.isPaywalled = false
            byokKeyStatuses = results
            byokActivationError = nil
          }
        } catch {
          await MainActor.run {
            byokKeyStatuses = results
            byokActivationError =
              "Não foi possível registrar as chaves no Omi. O plano gratuito continua desligado até o registro dar certo."
          }
        }
      } else if BYOKValidator.isTransient(results[selectedBYOKLLMProvider.provider] ?? .failed("missing")) {
        // The check produced no provider verdict (transport failure, provider
        // 5xx/429, offline). The key may be perfectly good: keep the existing
        // enrollment intact and say the check can be retried, instead of
        // treating a non-answer as a rejection and tearing the free plan down.
        await MainActor.run {
          byokKeyStatuses = results
          byokActivationError =
            "Não foi possível acessar \(selectedBYOKLLMProvider.displayName) para verificar sua chave. Suas chaves salvas continuam ativas, tente de novo em instantes."
        }
      } else {
        let failed = results.filter {
          if case .ok = $0.value { return false }
          return true
        }
        let names = failed.keys.map(\.displayName).sorted().joined(separator: ", ")
        try? await APIClient.shared.deactivateBYOK()
        APIKeyService.persistEnrolledFingerprints([:])
        await FloatingBarUsageLimiter.shared.fetchPlan()
        await MainActor.run {
          byokKeyStatuses = results
          byokActivationError =
            "Rejeitada pelo provedor: \(names). O plano gratuito continua desligado até o modelo de linguagem selecionado autenticar."
        }
      }

    case .deactivate:
      try? await APIClient.shared.deactivateBYOK()
      APIKeyService.persistEnrolledFingerprints([:])
      await FloatingBarUsageLimiter.shared.fetchPlan()
      await MainActor.run {
        byokKeyStatuses = [:]
        byokActivationError = nil
      }
    }

    await MainActor.run { loadSubscriptionInfo() }
  }

  func developerKeyField(
    provider: BYOKProvider? = nil,
    title: String, subtitle: String, settingId: String, value: Binding<String>
  ) -> some View {
    settingsCard(settingId: settingId) {
      VStack(alignment: .leading, spacing: OmiSpacing.sm) {
        HStack {
          Text(title)
            .scaledFont(size: OmiType.body, weight: .medium)
            .foregroundColor(Ink.primary)
          Spacer()
          if let provider, let status = byokKeyStatuses[provider] {
            byokStatusBadge(status)
          }
        }
        Text(subtitle)
          .scaledFont(size: OmiType.caption)
          .foregroundColor(Ink.secondary)
        SecureField("Deixe em branco para o padrão", text: value)
          .textFieldStyle(.roundedBorder)
          .scaledFont(size: OmiType.body)
        if let provider, case .failed(let msg) = byokKeyStatuses[provider] ?? .notChecked {
          Text(msg)
            .scaledFont(size: OmiType.caption)
            .foregroundColor(SettingsInk.notice)
        }
      }
    }
  }

  @ViewBuilder
  func byokStatusBadge(_ status: BYOKValidator.Status) -> some View {
    switch status {
    case .notChecked:
      EmptyView()
    case .checking:
      HStack(spacing: OmiSpacing.xxs) {
        ProgressView().controlSize(.mini)
        Text("Verificando…").scaledFont(size: OmiType.caption).foregroundColor(Ink.secondary)
      }
    case .ok:
      Text("Válida").scaledFont(size: OmiType.caption, weight: .semibold).foregroundColor(Ink.listeningGreen)
    case .failed:
      Text("Inválida").scaledFont(size: OmiType.caption, weight: .semibold).foregroundColor(SettingsInk.notice)
    case .transient:
      Text("Falha na verificação").scaledFont(size: OmiType.caption, weight: .semibold).foregroundColor(Ink.secondary)
    }
  }

}
