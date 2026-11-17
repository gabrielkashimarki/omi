import Foundation

extension Notification.Name {
  /// Posted after ~/.omi/mcp.json changes on disk — a server added, removed,
  /// retargeted, or re-authed from the UI, and a hand-edit noticed by
  /// `checkForExternalChanges()`. The agent runtime reads the file once per
  /// process spawn, so ChatProvider respawns it in response.
  static let omiUserMcpDidChange = Notification.Name("omiUserMcpDidChange")
}

/// Local MCP servers at `~/.omi/mcp.json`, in the standard client format:
/// `{"mcpServers": {"<name>": {"command", "args", "env"} | {"url", ...}}}`.
/// Hand-edits are respected: reads and writes go through read-modify-write on
/// the raw JSON so entries this UI does not understand survive untouched.
enum LocalMcpStore {
  struct Entry: Identifiable, Equatable, Sendable {
    let name: String
    /// "command …args" for stdio entries, the URL for remote ones.
    let summary: String
    let isCommand: Bool
    var id: String { name }
  }

  static var fileURL: URL { LocalSkillsStore.rootURL.appendingPathComponent("mcp.json") }

  static func listServers() -> [Entry] {
    let servers = readServers()
    return servers.keys.sorted().compactMap { name in
      guard let raw = servers[name] as? [String: Any] else { return nil }
      if let command = raw["command"] as? String {
        let args = (raw["args"] as? [Any])?.compactMap { $0 as? String } ?? []
        return Entry(name: name, summary: ([command] + args).joined(separator: " "), isCommand: true)
      }
      if let url = raw["url"] as? String {
        return Entry(name: name, summary: url, isCommand: false)
      }
      return nil
    }
  }

  /// Add a stdio server from a single command line ("npx @playwright/mcp@latest").
  static func addCommandServer(name: String, commandLine: String) throws {
    let slug = LocalSkillsStore.slugify(name)
    guard !slug.isEmpty else {
      throw storeError("O nome do servidor deve conter letras ou números")
    }
    let parts = try splitCommandLine(commandLine)
    guard let command = parts.first, !command.isEmpty else {
      throw storeError("Informe o comando a executar, por exemplo npx @playwright/mcp@latest")
    }
    var servers = readServers()
    var entry: [String: Any] = ["command": command]
    if parts.count > 1 { entry["args"] = Array(parts.dropFirst()) }
    servers[slug] = entry
    try writeServers(servers)
  }

  /// Split a command line into argv the way a shell would for the cases users
  /// hit: bare words, and runs quoted with `"` or `'` kept whole — a quoted
  /// path with spaces stays one argument, and a quote toggles quoting from
  /// anywhere in a word, so `--filter="App Store"` survives as one argument
  /// too. Backslash escapes are not interpreted; quote a path instead of
  /// escaping it. Runs of spaces or tabs separate words outside quotes. An
  /// unterminated quote is a typo that would mangle the command at spawn, so
  /// it throws rather than guessing.
  static func splitCommandLine(_ line: String) throws -> [String] {
    var parts: [String] = []
    var current = ""
    var inWord = false
    var quote: Character?
    for character in line {
      switch character {
      case "\"", "'":
        if let open = quote {
          if open == character { quote = nil } else { current.append(character) }
        } else {
          quote = character
          inWord = true
        }
      case " ", "\t":
        guard quote == nil else {
          current.append(character)
          continue
        }
        if inWord {
          parts.append(current)
          current = ""
          inWord = false
        }
      default:
        current.append(character)
        inWord = true
      }
    }
    guard quote == nil else {
      throw storeError("O comando tem uma aspa sem par")
    }
    if inWord { parts.append(current) }
    return parts
  }

  static func removeServer(name: String) {
    var servers = readServers()
    servers.removeValue(forKey: name)
    try? writeServers(servers)
  }

  static func upsertServer(_ name: String, entry: [String: Any]) throws {
    var servers = readServers()
    servers[name] = entry
    try writeServers(servers)
  }

  static func readAllServers() -> [String: Any] {
    readServers()
  }

  // MARK: - Raw file access

  private static func readServers() -> [String: Any] {
    guard let data = try? Data(contentsOf: fileURL),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return [:] }
    return json["mcpServers"] as? [String: Any] ?? [:]
  }

  private static func writeServers(_ servers: [String: Any]) throws {
    var root: [String: Any] = [:]
    if let data = try? Data(contentsOf: fileURL),
      let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    {
      root = existing
    }
    root["mcpServers"] = servers
    let fm = FileManager.default
    try fm.createDirectory(
      at: LocalSkillsStore.rootURL, withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    // The directory also holds auth material (token-bearing mcp.json, skills),
    // so it must not be world-listable — a directory that predates this
    // hardening keeps its looser mode, so re-assert on every write.
    try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: LocalSkillsStore.rootURL.path)
    let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    // The file carries OAuth access/refresh tokens and client secrets, so it
    // is user-only. The atomic rename replaces the file wholesale, so the
    // chmod must run on every write — it both sets the new file's mode and
    // tightens a file written by an older build.
    try data.write(to: fileURL, options: .atomic)
    try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    recordWriteFingerprint()
    notifyChanged()
  }

  // MARK: - Change notification

  private static let fingerprintLock = NSLock()
  // Guarded by `fingerprintLock`.
  private nonisolated(unsafe) static var lastWriteFingerprint: (modified: Date, size: Int)?

  /// Records the just-written file state so `checkForExternalChanges()` does
  /// not read our own write back as a hand-edit.
  private static func recordWriteFingerprint() {
    fingerprintLock.lock()
    defer { fingerprintLock.unlock() }
    lastWriteFingerprint = fileFingerprint()
  }

  private static func fileFingerprint() -> (modified: Date, size: Int)? {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
      let modified = attributes[.modificationDate] as? Date
    else { return nil }
    return (modified, attributes[.size] as? Int ?? 0)
  }

  /// Cheap source-of-truth check for edits made outside this process (the file
  /// is hand-editable by design, and nothing watches it). Call when the Apps
  /// page shows the server section: a stat, and a notification only when the
  /// file actually moved under us. The first observation in a process adopts
  /// the file silently — there is no earlier baseline to diff against.
  /// Returns whether an external change was detected.
  @discardableResult
  static func checkForExternalChanges() -> Bool {
    fingerprintLock.lock()
    defer { fingerprintLock.unlock() }
    let current = fileFingerprint()
    if current?.modified == lastWriteFingerprint?.modified, current?.size == lastWriteFingerprint?.size {
      return false
    }
    let hadBaseline = lastWriteFingerprint != nil
    lastWriteFingerprint = current
    guard hadBaseline else { return false }
    notifyChanged()
    return true
  }

  /// Test seam: clears the recorded fingerprint so a test process does not
  /// inherit another test's baseline.
  static func resetChangeDetectionForTesting() {
    fingerprintLock.lock()
    defer { fingerprintLock.unlock() }
    lastWriteFingerprint = nil
  }

  private static func notifyChanged() {
    if Thread.isMainThread {
      NotificationCenter.default.post(name: .omiUserMcpDidChange, object: nil)
    } else {
      DispatchQueue.main.async {
        NotificationCenter.default.post(name: .omiUserMcpDidChange, object: nil)
      }
    }
  }

  static func storeError(_ message: String) -> Error {
    NSError(domain: "LocalMcpStore", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }
}
