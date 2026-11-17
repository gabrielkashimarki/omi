import Foundation

/// Lembra chaves BYOK já recusadas pelo provedor para não anexá-las de novo a cada requisição.
@MainActor
final class CredentialHealthManager: ObservableObject {
  static let shared = CredentialHealthManager()

  private var invalidBYOKFingerprints: [BYOKProvider: String] = [:]

  private init() {}

  func reset() {
    invalidBYOKFingerprints.removeAll()
  }

  func canUseBYOK(provider: BYOKProvider, fingerprint: String?) -> Bool {
    guard let fingerprint, let invalid = invalidBYOKFingerprints[provider] else { return true }
    return invalid != fingerprint
  }
}
