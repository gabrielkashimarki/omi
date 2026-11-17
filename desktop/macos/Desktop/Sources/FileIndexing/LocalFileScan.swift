import Foundation

/// Varredura das pastas do usuário que alimenta o índice local de arquivos
/// (onboarding e "Reescanear" em Apps). Dispara os pedidos de acesso do macOS.
enum LocalFileScan {
  struct Outcome {
    let hasReadableUserFileTarget: Bool
    let didCompleteSuccessfully: Bool
    let indexedFileCount: Int
    /// Pastas do usuário (ex.: "~/Downloads") que o macOS não deixou ler.
    /// Alvos do sistema, como /Applications, ficam de fora.
    let deniedUserFolders: [String]
  }

  static func run(
    expectedOwnerID: String? = nil,
    authorizationSnapshot: RuntimeOwnerAuthorizationSnapshot? = nil
  ) async -> Outcome {
    func ownerChangedOutcome() -> Outcome {
      Outcome(
        hasReadableUserFileTarget: false,
        didCompleteSuccessfully: false,
        indexedFileCount: 0,
        deniedUserFolders: [])
    }
    func isAuthorized() -> Bool {
      !Task.isCancelled
        && OwnerCheck.isExpectedOwnerCurrent(expectedOwnerID, authorizationSnapshot: authorizationSnapshot)
    }

    guard isAuthorized() else { return ownerChangedOutcome() }
    let fm = FileManager.default
    let homeDir = fm.homeDirectoryForCurrentUser
    let scanTargets: [(label: String, pathForUser: String, url: URL, countsAsUserFileAccess: Bool)] = {
      var targets: [(String, String, URL, Bool)] = []

      let homeFolders = ["Downloads", "Documents", "Desktop", "Developer", "Projects"]
      for folder in homeFolders {
        let url = homeDir.appendingPathComponent(folder)
        if fm.fileExists(atPath: url.path) {
          targets.append((folder, "~/\(folder)", url, true))
        }
      }

      let applicationsURL = URL(fileURLWithPath: "/Applications")
      if fm.fileExists(atPath: applicationsURL.path) {
        targets.append(("Applications", "/Applications", applicationsURL, false))
      }

      // Apple Notes local stores (container + group container)
      let notesCandidates: [(String, String, URL, Bool)] = [
        (
          "Apple Notes (Container)",
          "~/Library/Containers/com.apple.Notes/Data/Library/Notes",
          homeDir.appendingPathComponent("Library/Containers/com.apple.Notes/Data/Library/Notes"),
          false
        ),
        (
          "Apple Notes (Group)",
          "~/Library/Group Containers/group.com.apple.notes",
          homeDir.appendingPathComponent("Library/Group Containers/group.com.apple.notes"),
          false
        ),
      ]
      for candidate in notesCandidates where fm.fileExists(atPath: candidate.2.path) {
        targets.append(candidate)
      }

      return targets
    }()

    // Pre-check folder access — this triggers macOS TCC dialogs
    var deniedFolders: [String] = []
    var deniedUserFolders: [String] = []
    var accessibleFolders: [URL] = []
    var readableUserFileTargetCount = 0
    for target in scanTargets {
      guard isAuthorized() else { return ownerChangedOutcome() }
      do {
        _ = try fm.contentsOfDirectory(
          at: target.url,
          includingPropertiesForKeys: [.fileSizeKey],
          options: [.skipsHiddenFiles]
        )
        accessibleFolders.append(target.url)
        if target.countsAsUserFileAccess {
          readableUserFileTargetCount += 1
        }
      } catch {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain && nsError.code == 257 {
          // Permission denied — TCC dialog was shown or already denied
          deniedFolders.append(target.pathForUser)
          if target.countsAsUserFileAccess {
            deniedUserFolders.append(target.pathForUser)
          }
        } else {
          // Other error (e.g. folder doesn't exist) — skip silently
          log("FileIndexer: Pre-check failed for \(target.label): \(error.localizedDescription)")
        }
      }
    }

    // Actually scan accessible folders (blocking)
    guard isAuthorized() else { return ownerChangedOutcome() }
    let shouldContinue: @Sendable () -> Bool = {
      !Task.isCancelled
        && OwnerCheck.isExpectedOwnerCurrent(expectedOwnerID, authorizationSnapshot: authorizationSnapshot)
    }
    let count = await FileIndexerService.shared.scanFolders(
      accessibleFolders,
      shouldContinue: shouldContinue)
    guard isAuthorized() else { return ownerChangedOutcome() }
    log(
      "Onboarding file scan completed: \(count) files indexed, \(deniedFolders.count) folders denied"
    )

    return Outcome(
      hasReadableUserFileTarget: readableUserFileTargetCount > 0,
      didCompleteSuccessfully: true,
      indexedFileCount: count,
      deniedUserFolders: deniedUserFolders)
  }
}
