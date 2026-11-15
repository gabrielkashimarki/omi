import OmiTheme
import SwiftUI

/// Where one summary action item stands relative to the reader's task list.
enum ActionItemTaskState: Equatable, Sendable {
  /// Not in the task list; the reader has not asked for it.
  case idle
  /// The reader asked; the task is being created.
  case adding
  /// Created from this summary in this session.
  case added
  /// The last attempt did not create a task.
  case failed
  /// Already backed by a task the detail can open.
  case linked

  /// Title of the trailing task control and of its accessibility action.
  var actionTitle: String {
    switch self {
    case .idle: return "Adicionar às Tarefas"
    case .adding: return "Adicionando"
    case .added: return "Adicionada"
    case .failed: return "Tentar de novo"
    case .linked: return "Abrir tarefa"
    }
  }

  /// Whether the task control does something when pressed in this state.
  var isActionable: Bool {
    switch self {
    case .idle, .failed, .linked: return true
    case .adding, .added: return false
    }
  }
}

/// Which trailing controls an action-item row draws.
///
/// A summary can list fifteen items; the same two buttons on every row is a wall. The controls
/// appear for the row under the pointer or holding keyboard focus. A row whose task state is
/// something the reader has to see — added, in flight, failed, or linked — keeps that control up.
/// Hidden controls keep their space, so revealing them never reflows the row.
enum ActionItemRowActionVisibility {
  static func showsTaskAction(state: ActionItemTaskState, isHovered: Bool, hasFocus: Bool) -> Bool {
    state != .idle || isHovered || hasFocus
  }

  static func showsTranscriptAction(isHovered: Bool, hasFocus: Bool) -> Bool {
    isHovered || hasFocus
  }
}

/// One action item in a conversation summary. It draws no card of its own: the Action Items
/// section groups its rows in one card with separators.
struct ConversationActionItemRow: View {
  let item: ActionItem
  /// The description as displayed (citation debris repaired); `item.description` stays the stored text.
  let displayDescription: String
  let taskState: ActionItemTaskState
  /// "Source" when the item cites transcript segments, otherwise "Transcript".
  let transcriptTitle: String
  let onTaskAction: () -> Void
  let onOpenTranscript: () -> Void

  private enum Control: Hashable {
    case task
    case transcript
  }

  @State private var isHovered = false
  @FocusState private var focusedControl: Control?

  var body: some View {
    let hasFocus = focusedControl != nil
    let showsTask = ActionItemRowActionVisibility.showsTaskAction(
      state: taskState, isHovered: isHovered, hasFocus: hasFocus)
    let showsTranscript = ActionItemRowActionVisibility.showsTranscriptAction(
      isHovered: isHovered, hasFocus: hasFocus)

    HStack(alignment: .firstTextBaseline, spacing: OmiSpacing.sm) {
      Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
        .scaledFont(size: OmiType.body)
        .foregroundColor(item.completed ? Ink.listeningGreen : Ink.secondary)
        .frame(width: 16)

      Text(displayDescription)
        .scaledFont(size: OmiType.body)
        .foregroundColor(item.completed ? Ink.secondary : Ink.primary)
        .strikethrough(item.completed, color: Ink.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)

      taskButton
        .focused($focusedControl, equals: .task)
        .opacity(showsTask ? 1 : 0)
        .allowsHitTesting(showsTask)

      transcriptButton
        .focused($focusedControl, equals: .transcript)
        .opacity(showsTranscript ? 1 : 0)
        .allowsHitTesting(showsTranscript)
    }
    .padding(.horizontal, OmiSpacing.md)
    .padding(.vertical, OmiSpacing.sm)
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
    .onHover { isHovered = $0 }
    // One element for VoiceOver: the item, its task state, and both controls as named actions,
    // so nothing depends on the pointer having revealed them.
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(displayDescription)
    .accessibilityValue(accessibilityStatus)
    .accessibilityAction(named: Text(taskState.actionTitle)) {
      if taskState.isActionable { onTaskAction() }
    }
    .accessibilityAction(named: Text("Abrir \(transcriptTitle)"), onOpenTranscript)
    .accessibilityIdentifier("action-item-row-\(item.id)")
  }

  private var accessibilityStatus: String {
    var parts: [String] = []
    if item.completed { parts.append("Concluída") }
    switch taskState {
    case .idle: break
    case .adding: parts.append("Adicionando às Tarefas")
    case .added: parts.append("Adicionada às Tarefas")
    case .failed: parts.append("Não foi possível adicionar às Tarefas")
    case .linked: parts.append("Nas Tarefas")
    }
    return parts.joined(separator: ", ")
  }

  private var taskIcon: String {
    switch taskState {
    case .idle: return "plus"
    case .adding: return "hourglass"
    case .added: return "checkmark"
    case .failed: return "exclamationmark.circle"
    case .linked: return "checklist"
    }
  }

  private var taskColor: Color {
    switch taskState {
    case .added: return Ink.listeningGreen
    case .failed: return Ink.errorRed
    case .idle, .adding, .linked: return Ink.secondary
    }
  }

  private var taskHelp: String {
    switch taskState {
    case .idle: return "Adicionar isto às suas tarefas"
    case .adding: return "Adicionando às suas tarefas"
    case .added: return "Já está nas suas tarefas"
    case .failed: return "Não foi possível adicionar isto às suas tarefas. Tente de novo"
    case .linked: return "Abrir a tarefa ligada a este item de ação"
    }
  }

  private var taskButton: some View {
    Button(action: onTaskAction) {
      HStack(spacing: OmiSpacing.xxs) {
        Image(systemName: taskIcon)
        Text(taskState.actionTitle)
      }
      .scaledFont(size: OmiType.caption, weight: .medium)
      .foregroundColor(taskColor)
    }
    .buttonStyle(.plain)
    .disabled(!taskState.isActionable)
    .opacity(taskState == .adding ? 0.5 : 1)
    .help(taskHelp)
  }

  private var transcriptButton: some View {
    Button(action: onOpenTranscript) {
      HStack(spacing: OmiSpacing.xxs) {
        Image(systemName: "text.quote")
        Text(transcriptTitle)
      }
      .scaledFont(size: OmiType.caption, weight: .medium)
      .foregroundColor(Ink.secondary)
    }
    .buttonStyle(.plain)
    .help((transcriptTitle == "Source" || transcriptTitle == "Fonte") ? "Mostrar onde isto foi dito" : "Abrir a transcrição completa")
  }
}
