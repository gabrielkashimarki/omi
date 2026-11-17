import XCTest

@testable import Omi_Computer

/// Verifies BYOK enrollment, owner binding, and paywall precedence.
@MainActor final class BYOKPaywallTests: XCTestCase {
  private let paywallKey = "desktop_isPaywalled"

  private func setAllBYOKKeys() {
    for p in BYOKProvider.allCases {
      UserDefaults.standard.set("sk-test-\(p.rawValue)", forKey: p.storageKey)
    }
  }

  private func clearAllBYOKKeys() {
    for p in BYOKProvider.allCases {
      UserDefaults.standard.removeObject(forKey: p.storageKey)
    }
  }

  /// `isByokActive` requires the selected provider's *current* key to match a
  /// fingerprint already persisted by `activateBYOK` reconciliation — raw
  /// UserDefaults presence alone is not enough (#11454 replaced the old
  /// all-keys-present check with this enrollment contract). Tests that
  /// exercise `isByokActive`/`isPaywalledEffective` must enroll the provider
  /// whose key they just set, and re-enroll whenever that key's value changes.
  private func enroll(_ p: BYOKProvider) {
    guard let key = APIKeyService.byokKey(p) else {
      XCTFail("enroll(\(p)) called before \(p.storageKey) was set")
      return
    }
    var fingerprints = APIKeyService.enrolledFingerprints()
    fingerprints[p.rawValue] = APIKeyService.byokFingerprint(key)
    APIKeyService.persistEnrolledFingerprints(fingerprints)
  }

  override func tearDown() async throws {
    CredentialHealthManager.shared.reset()
    clearAllBYOKKeys()
    UserDefaults.standard.removeObject(forKey: paywallKey)
    UserDefaults.standard.removeObject(forKey: .byokLLMProvider)
    UserDefaults.standard.removeObject(forKey: .byokOwnerUid)
    UserDefaults.standard.removeObject(forKey: .byokOwnerResetNotice)
    APIKeyService.persistEnrolledFingerprints([:])
  }

  func testByokActiveRequiresSelectedLLMKey() {
    clearAllBYOKKeys()
    XCTAssertFalse(APIKeyService.isByokActive)

    // A selected LLM key activates BYOK without the optional providers.
    UserDefaults.standard.set(BYOKLLMProvider.openrouter.rawValue, forKey: .byokLLMProvider)
    for p in BYOKProvider.allCases.dropLast() {
      UserDefaults.standard.set("k", forKey: p.storageKey)
    }
    enroll(.openrouter)
    XCTAssertTrue(APIKeyService.isByokActive)

    // All configured providers remain active. setAllBYOKKeys() rewrites
    // openrouter's key to "sk-test-openrouter", which invalidates the
    // fingerprint just enrolled above — re-enroll against the new value.
    setAllBYOKKeys()
    enroll(.openrouter)
    XCTAssertTrue(APIKeyService.isByokActive)
  }

  func testLegacyLLMSelectionInfersStoredProvider() {
    clearAllBYOKKeys()
    UserDefaults.standard.removeObject(forKey: .byokLLMProvider)
    UserDefaults.standard.set("sk-test-openai", forKey: BYOKProvider.openai.storageKey)

    XCTAssertEqual(APIKeyService.selectedBYOKLLMProvider, .openai)
  }

  func testBuildHeadersAttachSelectedLLMByokKey() async throws {
    clearAllBYOKKeys()
    UserDefaults.standard.set("sk-test-openai", forKey: BYOKProvider.openai.storageKey)
    enroll(.openai)

    let client = APIClient()
    await client.setTestAuthHeader("Bearer test-token")
    let headers = try await client.buildHeaders()

    XCTAssertEqual(headers[BYOKProvider.openai.headerName], "sk-test-openai")
  }

  func testBuildHeadersCanExplicitlyExcludeByokKeys() async throws {
    setAllBYOKKeys()

    let client = APIClient()
    await client.setTestAuthHeader("Bearer test-token")
    let headers = try await client.buildHeaders(includeBYOK: false)

    for provider in BYOKProvider.allCases {
      XCTAssertNil(headers[provider.headerName])
    }
  }

  func testLowLevelTransportDefaultsToExcludingByokKeys() async throws {
    setAllBYOKKeys()

    var transport = OmiHTTPTransport()
    transport.testAuthHeader = "Bearer test-token"
    let headers = try await transport.buildHeaders()

    for provider in BYOKProvider.allCases {
      XCTAssertNil(headers[provider.headerName])
    }
  }


  func testPaywallFlagSuppressedWhenByokActive() {
    // The exact bug: trial-expired flag set, then user configures BYOK keys.
    UserDefaults.standard.set(true, forKey: paywallKey)
    setAllBYOKKeys()
    // Explicit provider selection: with every provider's key set, legacy
    // inference (first BYOKLLMProvider.allCases with a key present) would
    // silently pick whichever provider we did not enroll.
    UserDefaults.standard.set(BYOKLLMProvider.openrouter.rawValue, forKey: .byokLLMProvider)
    enroll(.openrouter)
    XCTAssertFalse(
      AppState.isPaywalledEffective,
      "BYOK-active user must NOT be paywalled even with the flag set")
  }

  func testPaywallFlagAppliesWhenNotByok() {
    UserDefaults.standard.set(true, forKey: paywallKey)
    clearAllBYOKKeys()
    XCTAssertTrue(
      AppState.isPaywalledEffective,
      "Non-BYOK trial-expired user stays paywalled")
  }

  func testNotPaywalledWhenFlagUnset() {
    UserDefaults.standard.set(false, forKey: paywallKey)
    clearAllBYOKKeys()
    XCTAssertFalse(AppState.isPaywalledEffective)
  }

  func testRemovingDeepgramKeyLeavesSelectedLLMByokActive() {
    UserDefaults.standard.set(true, forKey: paywallKey)
    setAllBYOKKeys()
    // Explicit provider selection: with every provider's key set, legacy
    // inference (first BYOKLLMProvider.allCases with a key present) would
    // silently pick whichever provider we did not enroll.
    UserDefaults.standard.set(BYOKLLMProvider.openrouter.rawValue, forKey: .byokLLMProvider)
    enroll(.openrouter)
    XCTAssertFalse(AppState.isPaywalledEffective)

    // Deepgram is optional when a selected LLM key remains configured.
    UserDefaults.standard.removeObject(forKey: BYOKProvider.deepgram.storageKey)
    XCTAssertFalse(AppState.isPaywalledEffective)
  }

  func testHasTranscriptionBYOKRequiresEnrolledDeepgramFingerprint() {
    clearAllBYOKKeys()
    UserDefaults.standard.set(BYOKLLMProvider.openrouter.rawValue, forKey: .byokLLMProvider)
    UserDefaults.standard.set("sk-or", forKey: BYOKProvider.openrouter.storageKey)
    UserDefaults.standard.set("dg-rejected", forKey: BYOKProvider.deepgram.storageKey)
    APIKeyService.persistEnrolledFingerprints([:])

    XCTAssertFalse(
      APIKeyService.hasTranscriptionBYOK,
      "raw Deepgram presence must not suppress transcription exhaustion")

    let fp = APIKeyService.byokFingerprint("dg-rejected")
    APIKeyService.persistEnrolledFingerprints(["deepgram": fp])
    XCTAssertTrue(APIKeyService.hasTranscriptionBYOK)

    UserDefaults.standard.set("dg-rotated", forKey: BYOKProvider.deepgram.storageKey)
    XCTAssertFalse(
      APIKeyService.hasTranscriptionBYOK,
      "rotated Deepgram key is not enrolled until validation succeeds")
  }

  func testActiveSnapshotIncludesOnlyEnrolledCurrentFingerprints() {
    clearAllBYOKKeys()
    UserDefaults.standard.set(BYOKLLMProvider.openrouter.rawValue, forKey: .byokLLMProvider)
    UserDefaults.standard.set("sk-or", forKey: BYOKProvider.openrouter.storageKey)
    UserDefaults.standard.set("dg-original", forKey: BYOKProvider.deepgram.storageKey)
    APIKeyService.persistEnrolledFingerprints([:])

    XCTAssertTrue(APIKeyService.activeBYOKSnapshot.isEmpty)
    XCTAssertEqual(
      Set(APIKeyService.byokActivationCandidateSnapshot.keys),
      Set([.openrouter, .deepgram]),
      "configured keys remain validation candidates before enrollment")

    let openRouterFingerprint = APIKeyService.byokFingerprint("sk-or")
    APIKeyService.persistEnrolledFingerprints(["openrouter": openRouterFingerprint])
    XCTAssertEqual(Set(APIKeyService.activeBYOKSnapshot.keys), Set([.openrouter]))

    let deepgramFingerprint = APIKeyService.byokFingerprint("dg-original")
    APIKeyService.persistEnrolledFingerprints([
      "openrouter": openRouterFingerprint,
      "deepgram": deepgramFingerprint,
    ])
    XCTAssertEqual(Set(APIKeyService.activeBYOKSnapshot.keys), Set([.openrouter, .deepgram]))

    UserDefaults.standard.set("dg-rotated", forKey: BYOKProvider.deepgram.storageKey)
    XCTAssertEqual(
      Set(APIKeyService.activeBYOKSnapshot.keys),
      Set([.openrouter]),
      "a rotated Deepgram key stays out of runtime requests until validation enrolls it")

    UserDefaults.standard.set("dg-original", forKey: BYOKProvider.deepgram.storageKey)
    UserDefaults.standard.set("sk-or-rotated", forKey: BYOKProvider.openrouter.storageKey)
    XCTAssertEqual(
      Set(APIKeyService.activeBYOKSnapshot.keys),
      Set([.deepgram]),
      "each runtime capability independently requires its current enrolled fingerprint")
  }

  func testLegacyUnownedKeysAreClearedAndLeaveDurableReentryNotice() throws {
    clearAllBYOKKeys()
    UserDefaults.standard.removeObject(forKey: .byokOwnerUid)
    UserDefaults.standard.removeObject(forKey: .byokOwnerResetNotice)
    UserDefaults.standard.set("sk-legacy", forKey: BYOKProvider.openrouter.storageKey)

    APIKeyService.bindBYOKOwner("owner-a")

    XCTAssertNil(APIKeyService.byokKey(.openrouter))
    XCTAssertEqual(UserDefaults.standard.string(forKey: .byokOwnerUid), "owner-a")
    let notice = try XCTUnwrap(APIKeyService.pendingBYOKOwnerResetNotice(for: "owner-a"))
    XCTAssertEqual(notice.reason, .legacyUnownedKeys)
    XCTAssertNil(
      APIKeyService.pendingBYOKOwnerResetNotice(for: "owner-b"),
      "a credential-reset notice must never cross the owner boundary")
  }

  func testDifferentOwnerKeysAreClearedWithDifferentOwnerNotice() throws {
    clearAllBYOKKeys()
    UserDefaults.standard.set("owner-a", forKey: .byokOwnerUid)
    UserDefaults.standard.set("sk-owner-a", forKey: BYOKProvider.openrouter.storageKey)

    APIKeyService.bindBYOKOwner("owner-b")

    XCTAssertNil(APIKeyService.byokKey(.openrouter))
    XCTAssertEqual(UserDefaults.standard.string(forKey: .byokOwnerUid), "owner-b")
    XCTAssertEqual(
      try XCTUnwrap(APIKeyService.pendingBYOKOwnerResetNotice(for: "owner-b")).reason,
      .differentOwner)
  }

  func testTrocaDeDonoNaoApagaAsChavesDoJarvis() {
    clearAllBYOKKeys()
    UserDefaults.standard.set("owner-a", forKey: .byokOwnerUid)
    UserDefaults.standard.set("gm-jarvis", forKey: BYOKProvider.gemini.storageKey)
    UserDefaults.standard.set("dg-jarvis", forKey: BYOKProvider.deepgram.storageKey)

    APIKeyService.bindBYOKOwner("owner-b")

    XCTAssertEqual(APIKeyService.byokKey(.gemini), "gm-jarvis")
    XCTAssertEqual(APIKeyService.byokKey(.deepgram), "dg-jarvis")
    clearAllBYOKKeys()
  }

  func testOwnerBindingWithoutKeysDoesNotInventAResetNotice() {
    clearAllBYOKKeys()
    UserDefaults.standard.removeObject(forKey: .byokOwnerUid)
    UserDefaults.standard.removeObject(forKey: .byokOwnerResetNotice)

    APIKeyService.bindBYOKOwner("owner-a")

    XCTAssertEqual(UserDefaults.standard.string(forKey: .byokOwnerUid), "owner-a")
    XCTAssertNil(APIKeyService.pendingBYOKOwnerResetNotice(for: "owner-a"))
  }

  func testSameOwnerBindingPreservesKeysAndEnrollment() {
    clearAllBYOKKeys()
    UserDefaults.standard.set("owner-a", forKey: .byokOwnerUid)
    UserDefaults.standard.set("sk-owner-a", forKey: BYOKProvider.openrouter.storageKey)
    enroll(.openrouter)

    APIKeyService.bindBYOKOwner("owner-a")

    XCTAssertEqual(APIKeyService.byokKey(.openrouter), "sk-owner-a")
    XCTAssertEqual(
      APIKeyService.enrolledFingerprints()[BYOKProvider.openrouter.rawValue],
      APIKeyService.byokFingerprint("sk-owner-a"))
    XCTAssertNil(APIKeyService.pendingBYOKOwnerResetNotice(for: "owner-a"))
  }

  func testResetNoticePersistsUntilTheUserAcknowledgesIt() throws {
    clearAllBYOKKeys()
    UserDefaults.standard.removeObject(forKey: .byokOwnerUid)
    UserDefaults.standard.set("sk-legacy", forKey: BYOKProvider.openrouter.storageKey)
    APIKeyService.bindBYOKOwner("owner-a")
    let recorder = BYOKResetNoticeRecorder()

    APIKeyService().presentPendingBYOKOwnerResetNotice(for: "owner-a", through: recorder)

    XCTAssertEqual(recorder.title, "Re-add your custom API keys")
    XCTAssertTrue(recorder.message?.contains("Settings → Advanced → Developer Keys") == true)
    XCTAssertNotNil(
      APIKeyService.pendingBYOKOwnerResetNotice(for: "owner-a"),
      "launching the sheet must not lose the recovery instruction before it is read")

    try XCTUnwrap(recorder.completion)()
    XCTAssertNil(APIKeyService.pendingBYOKOwnerResetNotice(for: "owner-a"))
  }

  func testSelectedRealtimeBYOKKeyIgnoresUnselectedLeftover() {
    clearAllBYOKKeys()
    UserDefaults.standard.set(BYOKLLMProvider.openrouter.rawValue, forKey: .byokLLMProvider)
    UserDefaults.standard.set("sk-or", forKey: BYOKProvider.openrouter.storageKey)
    UserDefaults.standard.set("sk-openai-leftover", forKey: BYOKProvider.openai.storageKey)
    UserDefaults.standard.set("sk-gemini-leftover", forKey: BYOKProvider.gemini.storageKey)

    XCTAssertEqual(APIKeyService.selectedBYOKLLMProvider, .openrouter)
    XCTAssertNil(APIKeyService.selectedRealtimeBYOKKey(for: .openai))
    XCTAssertNil(APIKeyService.selectedRealtimeBYOKKey(for: .gemini))
    XCTAssertEqual(APIKeyService.selectedRealtimeBYOKKey(for: .openrouter), "sk-or")
  }

  /// The realtime hub speaks through OpenAI Realtime or Gemini Live and nothing else, so
  /// choosing one of those under Advanced → Voice Model is choosing that provider for
  /// voice. Withholding the key because the *text* provider is something the hub can
  /// never use — OpenRouter has no realtime API, and is the default — sent the turn to
  /// the managed lane, where it failed on Omi billing with the user's own key unspent.
  func testVoiceModelChoiceUnlocksItsOwnKeyWhileTextProviderDiffers() {
    clearAllBYOKKeys()
    UserDefaults.standard.set(BYOKLLMProvider.openrouter.rawValue, forKey: .byokLLMProvider)
    UserDefaults.standard.set("sk-or", forKey: BYOKProvider.openrouter.storageKey)
    UserDefaults.standard.set("sk-gemini-chosen", forKey: BYOKProvider.gemini.storageKey)

    XCTAssertEqual(APIKeyService.selectedBYOKLLMProvider, .openrouter)
    XCTAssertEqual(
      APIKeyService.selectedRealtimeBYOKKey(for: .gemini, chosenForVoice: true),
      "sk-gemini-chosen",
      "a provider chosen as the Voice Model must be able to use its own key")
  }

  /// The other direction, which is the whole reason the guard exists: the failover path
  /// does not pass `chosenForVoice`, so a key belonging to a provider the user picked
  /// nowhere is still never spent.
  func testFailoverStillRefusesAnUnchosenKey() {
    clearAllBYOKKeys()
    UserDefaults.standard.set(BYOKLLMProvider.openrouter.rawValue, forKey: .byokLLMProvider)
    UserDefaults.standard.set("sk-or", forKey: BYOKProvider.openrouter.storageKey)
    UserDefaults.standard.set("sk-openai-leftover", forKey: BYOKProvider.openai.storageKey)

    XCTAssertNil(
      APIKeyService.selectedRealtimeBYOKKey(for: .openai),
      "the failover must not spend a key the user chose neither for text nor for voice")
  }



}

@MainActor
private final class BYOKResetNoticeRecorder: DesktopAlertPresenting {
  private(set) var title: String?
  private(set) var message: String?
  private(set) var completion: (@MainActor () -> Void)?

  func present(title: String, message: String, completion: (@MainActor () -> Void)?) {
    self.title = title
    self.message = message
    self.completion = completion
  }
}
