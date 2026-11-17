import XCTest

@testable import Omi_Computer

@MainActor
final class SBOnboardingBackNavigationTests: XCTestCase {
  private let resumeStepKey = "sbOnboardingResumeStep"
  // Literals, not `SBOnboardingModel.*`: setUp/tearDown are nonisolated and
  // those constants are main-actor isolated. Mirrors this file's existing style.
  private let resumeSchemaKey = "sbOnboardingResumeStepSchema"
  private let currentResumeSchemaVersion = 2

  override func setUp() {
    super.setUp()
    UserDefaults.standard.removeObject(forKey: resumeStepKey)
    UserDefaults.standard.removeObject(forKey: DefaultsKey.onboardingHowDidYouHearSource)
    UserDefaults.standard.removeObject(forKey: DefaultsKey.onboardingRole)
    // These tests seed resume values in the *current* `Step` numbering. Without
    // the schema stamp, `begin()` would correctly read them as version-1 state
    // and renumber them, so the assertions below would be about a step nobody
    // wrote. Stamping says "this install is already current".
    UserDefaults.standard.set(currentResumeSchemaVersion, forKey: resumeSchemaKey)
  }

  override func tearDown() {
    UserDefaults.standard.removeObject(forKey: resumeStepKey)
    UserDefaults.standard.removeObject(forKey: resumeSchemaKey)
    UserDefaults.standard.removeObject(forKey: DefaultsKey.onboardingHowDidYouHearSource)
    UserDefaults.standard.removeObject(forKey: DefaultsKey.onboardingRole)
    super.tearDown()
  }

  func testBackFromPermissionsReturnsToRoleAndPreservesSelectedRole() {
    let model = SBOnboardingModel(
      appState: AppState(), onComplete: nil)
    UserDefaults.standard.set("Student", forKey: DefaultsKey.onboardingRole)
    model.step = .mic

    model.goBack()

    XCTAssertEqual(model.step, .role)
    XCTAssertEqual(model.role, "Student")
    XCTAssertEqual(
      UserDefaults.standard.integer(forKey: SBOnboardingModel.resumeStepKey),
      SBOnboardingModel.Step.role.rawValue)
  }

  func testBackPreservesEarlierAcquisitionChoiceAndStopsAtFirstStep() {
    let model = SBOnboardingModel(
      appState: AppState(), onComplete: nil)
    model.howHeard = "Friend"
    UserDefaults.standard.set("Friend", forKey: DefaultsKey.onboardingHowDidYouHearSource)
    model.step = .language

    model.goBack()

    XCTAssertEqual(model.step, .howHeard)
    XCTAssertEqual(model.howHeard, "Friend")

    model.step = .promise
    model.goBack()
    XCTAssertEqual(model.step, .promise)
  }

  func testBackNeverLandsOnAPermissionStepThatWasSkipped() {
    let appState = AppState()
    let model = SBOnboardingModel(appState: appState, onComplete: nil)
    appState.hasAccessibilityPermission = false
    appState.hasAutomationPermission = true
    appState.hasNotificationPermission = false
    model.step = .accessibility

    model.advance(userAnswer: nil, to: .automation)
    XCTAssertEqual(model.step, .notifications, "a granted Automation step is skipped")

    model.goBack()
    XCTAssertEqual(model.step, .accessibility, "Back returns to the step shown, not the skipped one")
    XCTAssertEqual(
      UserDefaults.standard.integer(forKey: SBOnboardingModel.resumeStepKey),
      SBOnboardingModel.Step.accessibility.rawValue)
  }

  func testProgressCountsOnlyShownStepsAndMovesOneDotPerAnswer() {
    let appState = AppState()
    let model = SBOnboardingModel(appState: appState, onComplete: nil)
    appState.hasAccessibilityPermission = false
    appState.hasAutomationPermission = true
    appState.hasNotificationPermission = true
    let allSteps = SBOnboardingModel.Step.allCases

    let start = model.progress
    XCTAssertEqual(start.current, 0)
    XCTAssertEqual(start.total, allSteps.filter { !model.wouldSkip($0) }.count)
    XCTAssertLessThanOrEqual(start.total, allSteps.count - 2, "granted permissions draw no dot")

    model.step = .accessibility
    model.shownStepHistory = model.predictedShownSteps(before: .accessibility)
    let before = model.progress

    model.advance(userAnswer: nil, to: .automation)
    XCTAssertEqual(model.step, .agents)
    XCTAssertEqual(model.progress.current, before.current + 1, "two skipped steps still move one dot")
    XCTAssertEqual(model.progress.total, before.total, "the dot count does not jump when steps are skipped")

    model.goBack()
    XCTAssertEqual(model.step, .accessibility)
    XCTAssertEqual(model.progress, before)
  }

  func testResumedRunSeedsHistoryWithoutSkippedSteps() {
    UserDefaults.standard.set(SBOnboardingModel.Step.agents.rawValue, forKey: resumeStepKey)
    let appState = AppState()
    appState.hasAccessibilityPermission = false
    appState.hasAutomationPermission = true
    appState.hasNotificationPermission = true
    let model = SBOnboardingModel(appState: appState, onComplete: nil)

    model.begin()

    XCTAssertEqual(model.step, .agents)
    XCTAssertFalse(model.shownStepHistory.contains(.automation))
    XCTAssertFalse(model.shownStepHistory.contains(.notifications))
    XCTAssertEqual(model.progress.current, model.shownStepHistory.count)
    model.goBack()
    XCTAssertEqual(model.step, .accessibility)
  }

}
