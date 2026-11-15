import OmiTheme
import SwiftUI
import UniformTypeIdentifiers

/// Stable report title for user feedback. Shared by the real `submitFeedback()`
/// path and the non-prod dry-run bridge action so the dry-run can never drift
/// from the title the real submit logs (SET-02).
func feedbackReportTitle(for _: String) -> String {
  "User Report"
}

/// Filename of the JSON diagnostics attachment produced by a feedback report.
/// Shared so the dry-run reports the same attachment name the real submit uses.
let feedbackDiagnosticsAttachmentFilename = "desktop_diagnostics.json"

/// Window controller for the feedback dialog
@MainActor
class FeedbackWindow {
  private static var window: NSWindow?

  static func show(userEmail: String?) {
    // Close existing window if any
    window?.close()

    // Track feedback opened
    AnalyticsManager.shared.feedbackOpened()

    let feedbackView = FeedbackView(userEmail: userEmail) {
      window?.close()
      window = nil
    }

    let hostingController = NSHostingController(rootView: feedbackView.withFontScaling())

    let newWindow = NSWindow(contentViewController: hostingController)
    newWindow.title = "Reportar problema"
    newWindow.styleMask = [.titled, .closable, .fullSizeContentView]
    // Transparent, light-pinned, and shadowed by its own frame. Without the pin an `NSTextField`
    // inside this sheet resolves `labelColor` against the machine's appearance and renders near-white
    // type on the near-white panel.
    WindowGlass.wear(newWindow, as: .titled)
    newWindow.setContentSize(NSSize(width: 400, height: 340))
    newWindow.center()
    newWindow.makeKeyAndOrderFront(nil)
    newWindow.level = .floating

    window = newWindow

    NSApp.activate()
  }
}

/// SwiftUI view for collecting user feedback and sending logs
struct FeedbackView: View {
  let userEmail: String?
  let onDismiss: () -> Void

  @State private var feedbackText: String = ""
  @State private var name: String = ""
  @State private var email: String = ""
  @State private var isSubmitting: Bool = false
  @State private var showSuccess: Bool = false
  @State private var savedReportPath: String?
  @State private var savedReportIncludesDiagnostics = false

  init(userEmail: String?, onDismiss: @escaping () -> Void) {
    self.userEmail = userEmail
    self.onDismiss = onDismiss
    // Pre-fill email from auth
    _email = State(initialValue: userEmail ?? "")
    // Pre-fill name from AuthService
    _name = State(initialValue: AuthService.shared.displayName)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: OmiSpacing.lg) {
      if showSuccess {
        // Result state
        VStack(spacing: OmiSpacing.md) {
          Image(
            systemName: savedReportPath == nil
              ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
          )
          .scaledFont(size: 48)
          .foregroundColor(savedReportPath == nil ? Ink.errorRed : Ink.listeningGreen)

          Text(savedReportPath == nil ? "Relatório não salvo" : "Relatório salvo neste Mac")
            .inkStyle(.firstTitle, color: Ink.primary)

          if let savedReportPath {
            Text(
              savedReportIncludesDiagnostics
                ? "Seu relatório não foi enviado. Uma cópia (sua nota mais o diagnóstico sem dados sensíveis) foi salva neste Mac em:\n\(savedReportPath)"
                : "Seu relatório não foi enviado. Sua nota foi salva neste Mac em:\n\(savedReportPath)\n\nNão foi possível gerar o diagnóstico sem dados sensíveis. Use \"Salvar diagnóstico…\" para capturá-lo."
            )
            .inkStyle(.prose, color: Ink.secondary)
            .textSelection(.enabled)
          } else {
            // The form state below still holds the entered note: send the user
            // back to it rather than dead-ending them behind a Close button.
            Text(
              "Não foi possível gravar o relatório no disco. Sua nota continua no formulário: volte, copie-a para um lugar seguro e use \"Salvar diagnóstico…\" para capturar o que der."
            )
            .inkStyle(.prose, color: Ink.secondary)
          }

          HStack {
            if savedReportPath == nil {
              Button("Voltar ao relatório") {
                showSuccess = false
                isSubmitting = false
              }
              .keyboardShortcut(.defaultAction)

              Button("Fechar") {
                onDismiss()
              }
            } else {
              Button("Fechar") {
                onDismiss()
              }
              .keyboardShortcut(.defaultAction)
            }
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        // Form state
        Text("Reportar um problema")
          .inkStyle(.rowCopy, color: Ink.primary)

        Text(
          "O diagnóstico sem dados sensíveis será incluído automaticamente. Notas, nome e e-mail ficam só neste dispositivo, por privacidade; salve um arquivo de diagnóstico para compartilhá-los manualmente."
        )
        .inkStyle(.statusLabel, color: Ink.secondary)

        TextEditor(text: $feedbackText)
          .font(.body)
          .frame(minHeight: 100)
          .border(Ink.hairline, width: 1)

        HStack {
          VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
            Text("Nome (opcional)")
              .inkStyle(.statusLabel, color: Ink.secondary)
            TextField("Seu nome", text: $name)
              .textFieldStyle(.roundedBorder)
          }

          VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
            Text("E-mail")
              .inkStyle(.statusLabel, color: Ink.secondary)
            TextField("seu@email.com", text: $email)
              .textFieldStyle(.roundedBorder)
          }
        }

        HStack {
          Button("Cancelar") {
            onDismiss()
          }
          .keyboardShortcut(.cancelAction)

          Button("Salvar diagnóstico…") {
            saveDiagnosticsLocally()
          }
          .help("Salva um relatório de diagnóstico sem dados sensíveis, localmente. Funciona offline e nada é enviado.")

          Spacer()

          Button("Salvar relatório") {
            submitFeedback()
          }
          .keyboardShortcut(.defaultAction)
          .disabled(isSubmitting)
        }
      }
    }
    .padding(OmiSpacing.xl)
    // Clear of the traffic lights, which `.fullSizeContentView` puts over the content.
    .padding(.top, OmiSpacing.lg)
    .frame(width: 400, height: 340)
    // The sheet paints no ground of its own; the glass owns it, full bleed because the window frame
    // already carries the corner and the shadow.
    .inkGlassPanel(cornerRadius: 0, shadow: nil)
  }

  /// A persisted report plus whether the redacted diagnostics bundle made it
  /// into the file. `diagnosticsIncluded == false` is a partial success the
  /// confirmation sheet must disclose, never paper over.
  struct PersistedReport: Equatable {
    let url: URL
    let diagnosticsIncluded: Bool
  }

  /// Write the report (note + redacted diagnostics bundle) under
  /// `Application Support/<bundle>/Feedback Reports/` so the user keeps a
  /// durable, shareable copy on their own machine. Best-effort: returns nil
  /// when the write fails, and flags a note-only file when the diagnostics
  /// bundle could not be generated or read.
  /// Not main-actor-isolated: submit runs this off the main thread (it reads
  /// and redacts up to 512 KB of log data and writes the file twice).
  @discardableResult
  nonisolated private static func persistLocalReport(
    title: String,
    note: String,
    name: String,
    email: String
  ) -> PersistedReport? {
    let fileManager = FileManager.default
    let applicationSupport =
      fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
    let bundleID = Bundle.main.bundleIdentifier ?? "com.omi.desktop"
    let reportsDir =
      applicationSupport
      .appendingPathComponent(bundleID, isDirectory: true)
      .appendingPathComponent("Feedback Reports", isDirectory: true)
    // Machine identifier, not user-facing text: ISO8601 keeps filenames
    // sortable and locale-independent.
    let stamp = ISO8601DateFormatter()
      .string(from: Date())
      .replacingOccurrences(of: ":", with: "-")
    let target = reportsDir.appendingPathComponent("report-\(stamp).txt")

    do {
      try fileManager.createDirectory(at: reportsDir, withIntermediateDirectories: true)
      var text = "title: \(title)\n"
      text += "created_at: \(ISO8601DateFormatter().string(from: Date()))\n"
      if !name.isEmpty { text += "name: \(name)\n" }
      if !email.isEmpty { text += "email: \(email)\n" }
      text += "\n\(note)\n"
      var diagnosticsIncluded = false
      if let diagnosticsURL = DesktopDiagnosticsManager.shared.writeIncidentDiagnosticsAttachment(
        area: "other",
        failureClass: "user_report",
        phase: "other")
      {
        defer { try? fileManager.removeItem(at: diagnosticsURL) }
        if let diagnosticsData = try? Data(contentsOf: diagnosticsURL),
          let diagnosticsText = String(data: diagnosticsData, encoding: .utf8)
        {
          text += "\n--- redacted diagnostics (desktop_diagnostics.json) ---\n"
          text += diagnosticsText
          text += "\n"
          diagnosticsIncluded = true
        } else {
          logError("Feedback report: diagnostics bundle was unreadable; saving note-only")
        }
      } else {
        logError("Feedback report: diagnostics bundle could not be generated; saving note-only")
      }
      try text.data(using: .utf8)?.write(to: target, options: .atomic)
      return PersistedReport(url: target, diagnosticsIncluded: diagnosticsIncluded)
    } catch {
      logError("Failed to persist local feedback report", error: error)
      return nil
    }
  }

  private func submitFeedback() {
    isSubmitting = true

    let message = feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)

    // Track feedback submitted
    AnalyticsManager.shared.feedbackSubmitted(feedbackLength: message.count)

    // With crash reporting removed, a report is retained locally on this
    // machine only: the note plus the bounded, redacted diagnostics bundle.
    // Nothing is transmitted anywhere; support shares the file manually.
    let reportTitle = feedbackReportTitle(for: message)
    let contactName = name
    let contactEmail = email
    // Building the report reads and redacts up to 512 KB of log data and
    // writes the file twice — keep that off the main thread exactly like
    // `saveDiagnosticsLocally()` does, and publish the result back on main.
    Task {
      let savedReportURL = await Task.detached(priority: .userInitiated) {
        let report = Self.persistLocalReport(
          title: reportTitle,
          note: message,
          name: contactName,
          email: contactEmail)
        if let savedReportURL = report {
          log(
            "User report saved locally: \(savedReportURL.url.path) diagnostics=\(savedReportURL.diagnosticsIncluded)"
          )
        } else {
          logError("User report could not be saved locally")
        }
        return report
      }.value

      OmiMotion.withGated {
        savedReportPath = savedReportURL?.url.path
        savedReportIncludesDiagnostics = savedReportURL?.diagnosticsIncluded ?? false
        showSuccess = true
        isSubmitting = false
      }
    }
  }

  /// Save a redacted diagnostics bundle to a user-chosen location and reveal it
  /// in Finder. Fully offline — no network — so users on named/dev
  /// bundles or without connectivity can still capture a report (BL-023 / SET-03).
  private func saveDiagnosticsLocally() {
    let panel = NSSavePanel()
    panel.title = "Salvar diagnóstico"
    panel.message = "Salve um relatório de diagnóstico sem dados sensíveis para compartilhar manualmente."
    panel.nameFieldStringValue = "omi-diagnostics-\(Self.exportTimestamp()).txt"
    panel.allowedContentTypes = [.plainText]
    panel.canCreateDirectories = true

    guard panel.runModal() == .OK, let url = panel.url else { return }

    // Building the bundle reads the log, serializes snapshots, and writes the
    // file — keep it off the main thread so a large log can't hang the UI. The
    // panel already returned; reveal in Finder back on main.
    DispatchQueue.global(qos: .userInitiated).async {
      let saved = DesktopDiagnosticsManager.shared.writeLocalDiagnosticsBundle(to: url)
      DispatchQueue.main.async {
        if saved {
          NSWorkspace.shared.activateFileViewerSelecting([url])
          log("Saved local diagnostics bundle to a user-chosen location")
        } else {
          log("Failed to save local diagnostics bundle")
        }
      }
    }
  }

  private static func exportTimestamp() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter.string(from: Date())
  }
}
