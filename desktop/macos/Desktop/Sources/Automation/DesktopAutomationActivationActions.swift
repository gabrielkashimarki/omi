//
//  DesktopAutomationActivationActions.swift — bridge actions for the first-48h activation surfaces.
//
//  Read/drive seams so a QA bundle can prove the surfaces without the cursor:
//  `daily_summary_snapshot` reports the shared daily-summary store shape-only,
//  `open_chat_prefilled` drives the one prefill-without-send entry
//  (`openMainAppChat(prefilledDraft:)`) so `chat_drafts_snapshot` can show the draft landed unsent,
//  `tap_chat_follow_up_chip` performs the chip's own send so the `followup` question origin is
//  observable end to end, and `seed_memory_review_fixture` / `memory_review_snapshot` /
//  `memory_review_vote` bring up and drive the "Things I learned today" rows. Every one is a
//  second caller of production code, never a second implementation.
//
//  Registered from `DesktopAutomationActionRegistry.registerBuiltins()`.
//

import AppKit
import Foundation
import OmiTheme

extension DesktopAutomationActionRegistry {

  func registerActivationActions() {
    register(
      name: "chat_timer_lifetime_probe",
      effects: [.localState],
      summary: "Verify common-runloop timer cancellation and invalidation when its owner is released",
      category: "chat",
      surfaces: ["main_chat"]
    ) { _ in
      let cancelled = OwnedRunLoopTimer.schedule(interval: 60) {}
      var released: OwnedRunLoopTimer? = OwnedRunLoopTimer.schedule(interval: 60) {}
      let releasedTimer = released?.timer
      let scheduled = cancelled.timer.isValid && releasedTimer?.isValid == true
      // Keep even a failing probe from leaving a source attached to the run loop.
      defer {
        cancelled.timer.invalidate()
        releasedTimer?.invalidate()
      }
      cancelled.cancel()
      released = nil
      return [
        "scheduled": String(scheduled),
        "cancelledValid": String(cancelled.timer.isValid),
        "releasedValid": String(releasedTimer?.isValid ?? true),
      ]
    }

    register(
      name: "daily_summary_snapshot",
      effects: [],
      summary: "Shape-only state of the shared daily-summary store (has summary, date, stat presence; no text)",
      category: "chat",
      surfaces: ["main_chat"]
    ) { _ in
      guard AppBuild.isNonProduction else {
        return ["error": "daily_summary_snapshot is disabled on production bundles"]
      }
      // Read only: no refresh here, because a refresh can post the "new summary" notch card.
      let store = ChatDailySummaryCoordinator.shared.store
      guard let latest = store.latest else {
        return [
          "hasSummary": "false",
          "isLoading": store.isLoading ? "true" : "false",
          "lastError": store.lastError ?? "",
        ]
      }
      return [
        "hasSummary": "true",
        // Opaque identity, not content: a harness uses it to drive the recap
        // route (`DailyRecapRouteRef`), whose page re-fetches by id.
        "summaryId": latest.id,
        "date": latest.date ?? "",
        "dateLabel": ChatDailySummaryPresentation.dateLabel(for: latest.date, now: Date()) ?? "",
        "headlineLength": String(latest.headline?.count ?? 0),
        "overviewLength": String(latest.overview?.count ?? 0),
        "hasStats": latest.stats == nil ? "false" : "true",
        "highlightCount": String(latest.highlights?.count ?? 0),
        "actionItemCount": String(latest.actionItems?.count ?? 0),
        // Count only, still no text. It is what makes `MemoryReviewSection.maxRows` observable:
        // the wire can carry more learned memories than the card ever renders, and without this
        // a flow cannot tell a card that bounded its rows from a day that produced only three.
        "memoriesLearnedCount": String(latest.memoriesLearned.count),
        "followUp": ChatDailySummaryPresentation.followUpQuestion(for: latest.date, now: Date()),
      ]
    }

    register(
      name: "open_daily_recap_page",
      effects: [.localState, .networkOrModel],
      summary:
        "Open the dedicated daily-recap page for a summary id through the typed recap route "
        + "(same `ChatFirstShellNavigation.openDailyRecap` the recap rows call)",
      params: ["recordID", "date"],
      category: "chat",
      surfaces: ["main_chat"]
    ) { params in
      guard AppBuild.isNonProduction else {
        return ["error": "open_daily_recap_page is disabled on production bundles"]
      }
      let recordID = params["recordID"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard !recordID.isEmpty else { return ["error": "missing 'recordID'"] }
      let date = params["date"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let before = ChatFirstShellNavigation.shared.route
      ChatFirstShellNavigation.shared.openDailyRecap(
        DailyRecapRouteRef(recordID: recordID, date: date))
      return [
        "requested": "true",
        "previousRoute": before.stableName,
        "route": ChatFirstShellNavigation.shared.route.stableName,
      ]
    }







    registerMemoryReviewActions()
  }

  // MARK: - Memory review card

  /// Bring up, read, and vote on the "Things I learned today" rows.
  ///
  /// The rows render only from a daily summary's `memories_learned`, and the only producer of that
  /// record is the nightly job — a day of conversations and a model call. So on a hermetic bundle
  /// the card was unreachable, and with it the row state machine, the three mutations, and the
  /// verdict read-back. `seed_memory_review_fixture` creates real memories through the production
  /// `POST /v3/memories` and hands their ids to the local-only daily-summary fixture, so the record
  /// arrives through the same `getDailySummaries` read production uses and every ✓ / ✗ addresses a
  /// memory that `/v3/memories/{id}/review` really mutates.
  private func registerMemoryReviewActions() {
    register(
      name: "seed_memory_review_fixture",
      effects: [.localState, .networkOrModel, .remoteWrite],
      summary:
        "Create `count` real memories and a local-only daily summary that learned them, then "
        + "refresh the shared store so the review card mounts (offline dev stack only)",
      params: ["count", "timeoutMs"],
      category: "chat",
      surfaces: ["main_chat"],
      sideEffects: ["creates memories on the signed-in local account"]
    ) { params in
      guard AppBuild.isNonProduction else {
        return ["error": "seed_memory_review_fixture is disabled on production bundles"]
      }
      let requested = Int(params["count"] ?? "") ?? MemoryReviewFixture.defaultCount
      guard let wanted = MemoryReviewFixture.rows(count: requested) else {
        return ["error": "count must be 1...\(MemoryReviewFixture.catalog.count)"]
      }

      var seeded: [MemoryReviewFixture.WireMemory] = []
      for row in wanted {
        do {
          let created = try await APIClient.shared.createMemory(
            content: row.content, category: row.category)
          seeded.append(
            .init(memoryID: created.id, content: row.content, category: row.category.rawValue))
        } catch {
          // Named stage, so a flow failure says which half of the fixture broke rather than
          // leaving an empty card to be read as "the card is broken".
          return [
            "error": "createMemory failed: \(MemoryReviewFixture.reason(error))",
            "createdCount": String(seeded.count),
          ]
        }
      }

      let response: MemoryReviewFixture.SeedResponse
      do {
        response = try await APIClient.shared.post(
          MemoryReviewFixture.seedEndpoint,
          body: MemoryReviewFixture.SeedRequest(memories: seeded))
      } catch {
        return [
          "error": "daily-summary fixture seed failed: \(MemoryReviewFixture.reason(error))",
          "createdCount": String(seeded.count),
        ]
      }

      // The store's own refresh, not the coordinator's: `ChatDailySummaryCoordinator.refresh()`
      // also announces a new summary as a notch card, and a harness must not fire the one
      // user-visible notification this surface owns.
      await ChatDailySummaryCoordinator.shared.store.refresh()

      let timeoutMs = Int(params["timeoutMs"] ?? "") ?? 8000
      let mountedRows = await MemoryReviewFixture.waitForMountedRows(
        seeded: Set(seeded.map(\.memoryID)), timeoutMs: timeoutMs)
      return [
        "createdCount": String(seeded.count),
        "summaryId": response.summaryID,
        "memoriesLearned": String(response.memoriesLearned),
        "mountedRows": String(mountedRows),
      ]
    }

    register(
      name: "memory_review_snapshot",
      effects: [],
      summary: "Rows the mounted 'Things I learned today' section bound, and the first two verdicts",
      params: [],
      category: "chat",
      surfaces: ["main_chat"]
    ) { _ in
      guard AppBuild.isNonProduction else {
        return ["error": "memory_review_snapshot is disabled on production bundles"]
      }
      guard let store = MemoryReviewCardRegistry.mounted else {
        return ["error": "no memory review section is mounted", "mounted": "false"]
      }
      var detail: [String: String] = [
        "mounted": "true",
        "source": store.source.rawValue,
        "rowCount": String(store.items.count),
        "maxRows": String(MemoryReviewSection.maxRows),
      ]
      for (index, item) in store.items.prefix(2).enumerated() {
        detail.merge(MemoryReviewFixture.rowDetail(index: index, item: item, store: store)) { current, _ in current }
      }
      return detail
    }

    register(
      name: "memory_review_vote",
      effects: [.localState, .networkOrModel, .remoteWrite],
      summary:
        "Vote on one mounted review row through the store the ✓ / ✗ buttons call, then report the "
        + "row once the mutation settles",
      params: ["row", "verdict", "timeoutMs"],
      category: "chat",
      surfaces: ["main_chat"]
    ) { params in
      guard AppBuild.isNonProduction else {
        return ["error": "memory_review_vote is disabled on production bundles"]
      }
      guard let store = MemoryReviewCardRegistry.mounted else {
        return ["error": "no memory review section is mounted", "mounted": "false"]
      }
      let index = Int(params["row"] ?? "") ?? 0
      guard store.items.indices.contains(index) else {
        return ["error": "row \(index) is outside the \(store.items.count) mounted rows"]
      }
      let raw = (params["verdict"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      guard let event = MemoryReviewFixture.event(for: raw) else {
        return ["error": "verdict must be 'accept' or 'reject'"]
      }

      let item = store.items[index]
      // The exact call the row's button makes (`MemoryReviewRowView.controls` → `send(.accept)` →
      // the section's closure). Nothing about the transition is re-decided here.
      store.send(event, to: item)
      let timeoutMs = Int(params["timeoutMs"] ?? "") ?? 15000
      let settled = await MemoryReviewFixture.waitForSettled(store: store, item: item, timeoutMs: timeoutMs)

      var detail = MemoryReviewFixture.rowDetail(index: index, item: item, store: store)
      detail["settledInTime"] = settled ? "true" : "false"
      return detail
    }
  }

}
