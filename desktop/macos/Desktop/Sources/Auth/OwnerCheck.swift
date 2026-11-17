import Foundation

/// Checagens de "o dono que pediu ainda é o dono da sessão", usadas antes de efeitos
/// físicos (preencher formulário, varrer arquivos, gravar no servidor).
enum OwnerCheck {
  static func isOwnerCurrent(
    _ expectedOwnerID: String,
    defaults: UserDefaults = .standard,
    allowAutomationOverride: Bool = AppBuild.isNonProduction
  ) -> Bool {
    let normalized = expectedOwnerID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return false }
    let authenticatedOwnerID = defaults.string(forKey: .authUserId)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return RuntimeOwnerIdentity.currentOwnerId(
      defaults: defaults,
      allowAutomationOverride: allowAutomationOverride) == normalized
      && authenticatedOwnerID == normalized
  }

  /// O dono esperado (ou o do snapshot de autorização) ainda é o dono atual da sessão.
  nonisolated static func isExpectedOwnerCurrent(
    _ expectedOwnerID: String?,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot? = nil
  ) -> Bool {
    if let authorizationSnapshot {
      return (expectedOwnerID == nil || authorizationSnapshot.ownerID == expectedOwnerID)
        && RuntimeOwnerIdentity.isAuthorizationCurrent(authorizationSnapshot)
    }
    guard let expectedOwnerID else { return true }
    return isOwnerCurrent(expectedOwnerID)
  }

  nonisolated static func ownerChangedResult() -> String {
    #"{"ok":false,"error":{"code":"authorized_execution_owner_changed","message":"The signed-in account changed while the authorized tool was executing."}}"#
  }
}
