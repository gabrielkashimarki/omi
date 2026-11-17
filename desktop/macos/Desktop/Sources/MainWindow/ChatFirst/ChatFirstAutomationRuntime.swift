import Combine
import Foundation

/// Non-production semantic actions for the live Chat-first shell. The runtime
/// owns no fixture data and makes no eligibility decision: it is installed only
/// after the root has consumed the server-owned capability sample. Individual
/// pages register their real handlers while mounted, so an action cannot claim
/// a result for an off-screen or fabricated surface.
@MainActor
final class ChatFirstAutomationRuntime: ObservableObject {
  typealias AsyncBool = @MainActor () async -> Bool
  typealias CaptureSnapshot = @MainActor () -> Bool

  private let navigation: ChatFirstShellNavigation
  private let goalsStore: CanonicalGoalsStore
  private let tasksStore: TasksStore

  private var setFocus: AsyncBool?
  private var openRelatedTasks: AsyncBool?
  private var toggleTask: AsyncBool?
  private var openCapture: AsyncBool?
  private var captureDetailIsVisible: CaptureSnapshot?

  init(
    navigation: ChatFirstShellNavigation,
    goalsStore: CanonicalGoalsStore,
    tasksStore: TasksStore
  ) {
    self.navigation = navigation
    self.goalsStore = goalsStore
    self.tasksStore = tasksStore
  }

  func install() {
    // The semantic fixture actions are part of the loopback bridge contract,
    // not a generic non-production feature. Preview/release-style bundles
    // must never register them, even if code elsewhere calls this runtime.
    guard DesktopAutomationLaunchOptions.isEnabled else { return }
    let registry = DesktopAutomationActionRegistry.shared

    registry.register(
      name: "chat_first_runtime_snapshot",
      effects: [],
      summary: "Read shape-only state from the live Chat-first pages",
      category: "read",
      surfaces: ["goals", "tasks", "conversations"],
      sideEffects: []
    ) { [weak self] _ in
      guard let self else { return nil }
      return self.runtimeSnapshot()
    }

    registry.register(
      name: "chat_first_set_focus",
      effects: [.localState, .networkOrModel, .remoteWrite],
      summary: "Set focus through the currently visible Chat-first Goals page",
      category: "coordinator",
      surfaces: ["goals"],
      sideEffects: ["updates canonical goal focus"]
    ) { [weak self] _ in
      guard let self, let setFocus = self.setFocus else {
        throw DesktopAutomationActionError.invalidParams("chat_first_goals_page_not_visible")
      }
      return ["focus_updated": await setFocus() ? "true" : "false"]
    }

    registry.register(
      name: "chat_first_open_related_tasks",
      effects: [.localState, .networkOrModel, .remoteWrite],
      summary: "Open related Tasks through the currently visible focused Goal",
      category: "coordinator",
      surfaces: ["goals", "tasks"],
      sideEffects: ["changes Chat-first route"]
    ) { [weak self] _ in
      guard let self, let openRelatedTasks = self.openRelatedTasks else {
        throw DesktopAutomationActionError.invalidParams("chat_first_goal_detail_not_visible")
      }
      guard await openRelatedTasks() else {
        return ["related_tasks_opened": "false"]
      }
      return ["related_tasks_opened": await self.waitForVisibleRoute(.tasks) ? "true" : "false"]
    }

    registry.register(
      name: "chat_first_toggle_task",
      effects: [.localState, .networkOrModel, .remoteWrite],
      summary: "Toggle one visible Chat-first task through the shared Tasks store",
      category: "coordinator",
      surfaces: ["tasks"],
      sideEffects: ["updates task completion"]
    ) { [weak self] _ in
      guard let self, let toggleTask = self.toggleTask else {
        throw DesktopAutomationActionError.invalidParams("chat_first_tasks_page_not_visible")
      }
      return ["task_reconciled": await toggleTask() ? "true" : "false"]
    }

    registry.register(
      name: "chat_first_open_capture",
      effects: [.localState, .networkOrModel],
      summary: "Select an Omi-device capture through the visible archive page",
      category: "coordinator",
      surfaces: ["conversations"],
      sideEffects: ["selects a local capture detail"]
    ) { [weak self] _ in
      guard let self, let openCapture = self.openCapture else {
        throw DesktopAutomationActionError.invalidParams("chat_first_capture_page_not_visible")
      }
      return ["capture_detail_opened": await openCapture() ? "true" : "false"]
    }

  }

  func uninstall() {
    let registry = DesktopAutomationActionRegistry.shared
    for name in [
      "chat_first_runtime_snapshot",
      "chat_first_set_focus",
      "chat_first_open_related_tasks",
      "chat_first_toggle_task",
      "chat_first_open_capture",
    ] {
      registry.unregister(name)
    }
    unregisterGoalsPage()
    unregisterTasksPage()
    unregisterCapturePage()
  }

  func registerGoalsPage(setFocus: @escaping AsyncBool, openRelatedTasks: @escaping AsyncBool) {
    self.setFocus = setFocus
    self.openRelatedTasks = openRelatedTasks
  }

  func unregisterGoalsPage() {
    setFocus = nil
    openRelatedTasks = nil
  }

  func registerTasksPage(toggleTask: @escaping AsyncBool) {
    self.toggleTask = toggleTask
  }

  func unregisterTasksPage() {
    toggleTask = nil
  }

  func registerCapturePage(
    openCapture: @escaping AsyncBool,
    detailIsVisible: @escaping CaptureSnapshot
  ) {
    self.openCapture = openCapture
    captureDetailIsVisible = detailIsVisible
  }

  func unregisterCapturePage() {
    openCapture = nil
    captureDetailIsVisible = nil
  }

  private func runtimeSnapshot() -> [String: String] {
    [
      "route": navigation.route.stableName,
      "route_visible": navigation.visibleRoute == navigation.route ? "true" : "false",
      "focus_acknowledged": navigation.isFocusedEntityAcknowledged ? "true" : "false",
      "focused_goal_available": goalsStore.primaryFocusedGoal == nil ? "false" : "true",
      "visible_task_count": "\(tasksStore.tasks.filter { !$0.isRetired }.count)",
      "completed_visible_task_count": "\(tasksStore.tasks.filter { !$0.isRetired && $0.completed }.count)",
      "capture_detail_visible": captureDetailIsVisible?() == true ? "true" : "false",
    ]
  }

  private func waitForVisibleRoute(_ route: ChatFirstRoute, timeoutMs: Int = 5_000) async -> Bool {
    let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1_000)
    while Date() < deadline {
      if navigation.visibleRoute == route { return true }
      try? await Task.sleep(nanoseconds: 50_000_000)
    }
    return navigation.visibleRoute == route
  }
}
