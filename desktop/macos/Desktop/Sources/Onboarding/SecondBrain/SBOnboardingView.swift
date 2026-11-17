import AppKit
import OmiTheme
import SwiftUI

enum SBOnboardingRepository {
  static let url = URL(string: "https://github.com/BasedHardware/omi")!
}

enum SBOnboardingPanelLayout {
  static let maximumSize = CGSize(width: 540, height: 640)
  static let horizontalInset: CGFloat = 24
  static let verticalInset: CGFloat = 20

  static func size(in availableSize: CGSize) -> CGSize {
    CGSize(
      width: min(maximumSize.width, max(0, availableSize.width - horizontalInset * 2)),
      height: min(maximumSize.height, max(0, availableSize.height - verticalInset * 2))
    )
  }
}

/// The Second Brain conversational onboarding — a chat with Omi that streams
/// word-by-word and performs real side-effects. Replaces the legacy wizard.
///
/// **It paints exactly one ground, and that ground is the app's glass.** A full-bleed dune photograph
/// under a black gradient used to sit behind this card, and every label on the very first screen a
/// new user reaches had to be white to survive it. The art is gone and the type is near-black:
/// blurred desktop, one card, two rungs of ink.
///
/// The card itself was `Color.white.opacity(0.05)` over `.ultraThinMaterial`. That is *within-window*
/// vibrancy — it frosts the app's own content rather than the desktop — so it was never the same
/// material as the panel around it. It became a bare wash-and-hairline `glassCard`, which was right
/// while `ShellGlassGround` made the whole window one slab of glass and a second scrim would have
/// spent the passthrough budget twice. `ShellWindowChrome` retired that slab and handed every other
/// destination its own panel (`PageGlassLane`); this card was missed, so a wash over nothing left the
/// user's wallpaper as the ground and the copy unreadable over a bright photograph. It is
/// `onboardingCard()`, which is `inkGlassPanel` — the one shared piece of glass, once.
struct SBOnboardingView: View {
  @StateObject private var model: SBOnboardingModel
  @ObservedObject private var importConnectorStatusStore: ImportConnectorStatusStore
  @State private var selectedImportConnector: ImportConnector?
  /// Language step: false shows the detected default + Continue; true reveals the picker.
  @State private var languageChanging = false
  @State private var showAIAssistants = false

  init(
    appState: AppState,
    importConnectorStatusStore: ImportConnectorStatusStore,
    onComplete: (() -> Void)?
  ) {
    _model = StateObject(
      wrappedValue: SBOnboardingModel(
        appState: appState,
        importConnectorStatusStore: importConnectorStatusStore,
        onComplete: onComplete
      ))
    _importConnectorStatusStore = ObservedObject(wrappedValue: importConnectorStatusStore)
  }

  var body: some View {
    GeometryReader { geometry in
      let panelSize = SBOnboardingPanelLayout.size(in: geometry.size)
      panel(in: panelSize)
        .frame(width: panelSize.width, height: panelSize.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    // Pins the panel's light appearance so `Ink`'s dynamic colours resolve dark here even on a
    // machine in Dark Mode. Without it this card is near-white type on a near-white ground.
    .glassContent()
    .onAppear { model.begin() }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      if model.step == .context {
        refreshContextStates()
      }
      // Granting a permission means leaving Omi for System Settings and coming
      // back, so this return is the signal a grant may have landed — not a 20s
      // poll that Full Disk Access and Accessibility routinely outlive.
      model.recheckActivePermission()
    }
    .onChange(of: model.step) { _, step in
      if step == .context { refreshContextStates() }
    }
    .onChange(of: model.contextStates) { oldStates, newStates in
      guard model.step == .context else { return }
      if SBOnboardingModel.shouldRefocusContext(from: oldStates, to: newStates) {
        PermissionDragGuidance.returnToOmi()
      }
    }
    .onReceive(importConnectorStatusStore.connectorDidSync) { connectorID in
      model.markPersistedContextConnectorConnected(connectorID)
      let contextID = connectorID == "email" ? "gmail" : connectorID
      if model.step == .context, model.contextStates[contextID] == "on" {
        PermissionDragGuidance.returnToOmi()
      }
    }
    .dismissableSheet(item: $selectedImportConnector) { connector in
      ImportConnectorSheet(
        connector: connector,
        appState: nil,
        statusStore: importConnectorStatusStore,
        onDismiss: { selectedImportConnector = nil }
      )
      .frame(width: 520, height: 620)
    }
  }

  private func panel(in panelSize: CGSize) -> some View {
    VStack(spacing: 0) {
      // Navigation belongs to the onboarding card, not the window's corner. The window can be wider
      // than the card (and may be repositioned independently), so an outer overlay makes Back look
      // detached from the conversation it controls.
      // Back on the leading edge, where every way back in the app sits; Skip Setup trailing.
      HStack {
        backButton
        Spacer(minLength: 8)
        if model.canSkipOnboarding { skipButton }
      }
      .frame(minHeight: 44)
      .padding(.horizontal, 16)
      .padding(.top, 8)
      ScrollViewReader { proxy in
        ScrollView {
          VStack(alignment: .leading, spacing: 14) {
            ForEach(model.thread) { msg in
              messageRow(msg)
            }
            if let streaming = model.streamingText {
              omiRow(streaming)
            }
            if model.typing {
              HStack(spacing: 10) {
                SBLogo(size: 16, spinning: true)
                Text("Omi está digitando…").inkStyle(InkType.statusLabel, color: Ink.secondary)
              }
            }
            if model.showWidget {
              currentStepContainer(in: panelSize)
                .id("widget")
            }
            // Keep the last control above the progress band while ScrollViewReader settles after a
            // growing widget or a streamed message. A tiny sentinel spacer can leave an input or
            // permission action visually underneath the dots even though the band is a VStack
            // sibling, so reserve a full band's height plus a small breathing room here as well.
            Color.clear.frame(height: OnboardingGlass.scrollContentBottomPadding).id("bottom")
          }
          .padding(.horizontal, 28).padding(.top, 26)
        }
        // **The thread sits on the floor of the card, not its ceiling.** The panel is a fixed
        // 540 × 640 so it never jumps as the conversation grows, which means the first three steps
        // — the first screens a new user ever sees — otherwise draw one short paragraph at the top
        // of a card with ~380 pt of visibly empty card under it. Emptiness a border draws a box
        // around is not whitespace, it is an unfinished panel. Anchored to the bottom, a short
        // thread reads the way every chat does before you scroll, and the action the step is asking
        // for lands near the thumb instead of stranded mid-card.
        .defaultScrollAnchor(.bottom)
        .onChange(of: model.thread.count) { _, _ in scrollDown(proxy) }
        .onChange(of: model.showWidget) { _, _ in scrollDown(proxy) }
        .onChange(of: model.streamingText) { _, _ in scrollDown(proxy) }
        // Revealing the assistants list grows the widget *below* the fold, so without this the
        // rows it just opened are clipped by the card's lower edge and nothing moves.
        .onChange(of: showAIAssistants) { _, _ in scrollDown(proxy) }
        // The same rule for every widget that grows without touching the thread — a finished file
        // scan, a permission row turning into the relaunch offer, the demo arming its chord. See
        // `SBOnboardingModel.widgetShape`: without it the Files step's Continue renders below the
        // card's lower edge and the step reads as having no way forward.
        .onChange(of: model.widgetShape) { _, _ in scrollDown(proxy) }
      }
      // Context imports can send the user to a browser and grow row details. Keep the exit
      // outside the scrolling thread so neither a pending import nor long failure copy hides it.
      if model.step == .context {
        SBInkButton(title: "Continuar", isDefaultAction: true) { model.answerContext() }
          .padding(.horizontal, 28)
          .padding(.vertical, 12)
      }
      // The band is a sibling of the scroll view, not an overlay on its content. It always claims the
      // same height, including while a step is streaming, so the current-step column never jumps when
      // one widget is replaced by the next.
      // Counts the steps this run shows, not `Step.allCases`: a granted permission is skipped, and a
      // dot for it would make the band jump (`SBOnboardingModel.progress`).
      OnboardingProgressBand(total: model.progress.total, current: model.progress.current)
    }
    // One shadow, and it is `InkGlassShadow.ambient` — the same broad, diffuse one every floating
    // panel in this app casts, drawn by `onboardingCard`. Not the 60 pt black drop this used to carry
    // inside itself, which read as depth on the dark art and as dirt on glass.
    .onboardingCard()
  }

  /// The one current-step container. `model.step` is the live onboarding identity; giving the widget
  /// that identity lets SwiftUI run the shared height-relative transition when the model advances or
  /// goes back, while the fixed panel size keeps the visual drift proportional across window sizes.
  @ViewBuilder
  private func currentStepContainer(in panelSize: CGSize) -> some View {
    widget
      .padding(.leading, 26).padding(.top, 2)
      .id(model.step)
      .transition(.onboardingStep(in: panelSize))
      .animation(OnboardingGlass.stepAnimation, value: model.step)
      .animation(OnboardingGlass.stepAnimation, value: model.showWidget)
  }

  /// Back and Skip sit in the card header, next to the conversation they control. `glassChip()` is a
  /// wash — the treatment for a chip that already sits on a ground — and the card is already the
  /// ground here. `.glassFloatingBar` keeps the compact control legible without making it look like a
  /// second panel.
  private static let chipRadius: CGFloat = 999

  @ViewBuilder private var backButton: some View {
    if model.canGoBack {
      Button(action: { model.goBack() }) {
        Text("‹ Voltar")
          .inkStyle(InkType.statusLabel, color: Ink.secondary)
          .padding(.horizontal, 14).padding(.vertical, 7)
          .glassFloatingBar(cornerRadius: Self.chipRadius)
      }
      .buttonStyle(.plain)
      .help("Voltar e mudar uma resposta anterior")
    }
  }

  private var skipButton: some View {
    Button(action: { model.skip() }) {
      // "Skip Setup", not "Skip": the per-step links say "Skip for now", and the two look alike while
      // meaning very different amounts.
      Text("Pular configuração")
        .inkStyle(InkType.statusLabel, color: Ink.secondary)
        .padding(.horizontal, 14).padding(.vertical, 7)
        .glassFloatingBar(cornerRadius: Self.chipRadius)
    }
    .buttonStyle(.plain)
    .help("Pular a introdução e ir para o seu segundo cérebro")
  }

  private func scrollDown(_ proxy: ScrollViewProxy) {
    OmiMotion.perform(.standard) { proxy.scrollTo("bottom", anchor: .bottom) }
  }

  @ViewBuilder private func messageRow(_ msg: SBOnboardingModel.Msg) -> some View {
    if msg.isOmi { omiRow(msg.text) } else { meRow(msg.text) }
  }

  /// Omi's turn. `prose` is the one role that carries paragraphs, and it is the reading rung — this
  /// is a sentence someone reads, not a label they glance at.
  private func omiRow(_ text: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
      SBLogo(size: 16, opacity: 0.9)
      Text(text).inkStyle(InkType.prose, color: Ink.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 380, alignment: .leading)
      Spacer(minLength: 0)
    }
  }

  /// The user's own turn, which is why it is `primary` against Omi's `secondary`: on this card the
  /// thing you said is the thing you look back for.
  private func meRow(_ text: String) -> some View {
    HStack {
      Spacer(minLength: 40)
      Text(text).inkStyle(InkType.rowCopy, color: Ink.primary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 13).padding(.vertical, 8)
        .glassRow(.selected)
    }
  }

  // MARK: - Widgets per step

  @ViewBuilder private var widget: some View {
    switch model.step {
    case .promise: promiseWidget
    case .name: nameWidget
    case .howHeard: howHeardWidget
    case .language: languageWidget
    case .role: roleWidget
    case .mic:
      permStepWidget("microphone", "Microfone", "para eu ouvir o seu lado das conversas") { model.answerMic() }
    case .systemAudio:
      permStepWidget("system_audio", "Áudio do sistema", "para eu ouvir o outro lado das chamadas, como Zoom e Meet") {
        model.answerSystemAudio()
      }
    case .screen:
      permStepWidget("screen_recording", "Gravação de Tela", "para eu ver o que você está olhando") {
        model.answerScreen()
      }
    case .files: filesWidget
    case .accessibility:
      permStepWidget("accessibility", "Acessibilidade", "para eu captar seu atalho e clicar ou digitar por você") {
        model.answerAccessibility()
      }
    case .automation:
      permStepWidget("automation", "Automação", "para eu ajudar com tarefas nos apps que você escolher") {
        model.answerAutomation()
      }
    case .notifications:
      permStepWidget("notifications", "Notificações", "um resumo no fim do dia, nos dias em que você gravar uma conversa") {
        model.answerNotifications()
      }
    case .agents: agentsWidget
    case .context: contextWidget
    case .capture: captureWidget
    case .referral: referralWidget
    }
  }

  private var promiseWidget: some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(spacing: 0) {
        trustRow("ABERTO") {
          HStack(spacing: 0) {
            Text("Cada linha minha está no ")
            Link("GitHub", destination: SBOnboardingRepository.url)
              .underline()
            Text(".")
          }
        }
        // `GlassSeparator`, not `Divider()`: a `Divider` inherits the host window's appearance rather
        // than the panel's pinned one, so on a Dark machine it draws a light rule on a light card.
        GlassSeparator()
        trustRow("PRIVADO") { Text("Seus dados são criptografados e só seus.") }
        GlassSeparator()
        trustRow("SEU") { Text("Me pause quando quiser. Apague qualquer coisa, para sempre.") }
      }
      .glassCard(cornerRadius: PageGlass.rowRadius)
      SBInkButton(title: "Configurar o Omi →", isDefaultAction: true) { model.answerPromise() }
    }
  }

  private func trustRow<Content: View>(_ tag: String, @ViewBuilder content: () -> Content) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Text(tag).inkFont(InkType.statusLabel).foregroundStyle(Ink.secondary).frame(
        width: 52, alignment: .leading)
      // The promise is the copy this whole step exists for, so it never truncates — `PRIVATE` used to
      // carry `.lineLimit(1)` and lost its second half at any narrow width.
      content().inkStyle(InkType.rowCopy, color: Ink.primary)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 14).padding(.vertical, 12)
  }

  private var nameWidget: some View {
    HStack(spacing: 8) {
      TextField("seu nome", text: $model.nameDraft)
        .textFieldStyle(.plain).inkStyle(InkType.rowCopy, color: Ink.primary)
        .padding(.horizontal, 13).padding(.vertical, 9)
        .glassField()
        .onSubmit { model.answerName() }
      SBInkButton(title: "→", horizontalPadding: 15, verticalPadding: 9) { model.answerName() }
        .accessibilityLabel("Continuar")
    }
    .frame(maxWidth: 360, alignment: .leading)
  }

  private var howHeardWidget: some View {
    FlowChips(items: SBOnboardingModel.howHeardSources, selectedItem: model.howHeard) { source in
      model.pickHowHeard(source)
    }
  }

  private var languageWidget: some View {
    let all = AssistantSettings.supportedLanguages
    let draft = model.languageDraft.trimmingCharacters(in: .whitespaces)
    return VStack(alignment: .leading, spacing: 12) {
      if !languageChanging, !draft.isEmpty {
        // Auto-detected default: accept with one tap, or reveal the picker.
        HStack(spacing: 8) {
          Text(draft).inkStyle(InkType.prose, color: Ink.primary)
          if model.languageIsDetectedFromMac {
            Text(SBOnboardingLanguageCopy.detectedLanguageDetail)
              .inkStyle(InkType.statusLabel, color: Ink.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        SBInkButton(title: SBOnboardingLanguageCopy.continueAction(for: draft), isDefaultAction: true) {
          if let m = all.first(where: { $0.name.lowercased() == draft.lowercased() }) {
            model.pickLanguage(code: m.code, name: m.name)
          } else {
            model.answerLanguageText()
          }
        }
        Button {
          languageChanging = true
        } label: {
          Text(SBOnboardingLanguageCopy.changeSpokenLanguageAction)
            .inkStyle(InkType.statusLabel, color: Ink.secondary)
        }
        .buttonStyle(.plain)
      } else {
        let filter = draft.lowercased()
        let matches: [(code: String, name: String)] =
          filter.isEmpty
          ? Array(all.prefix(6))
          : Array(
            all.filter { $0.name.lowercased().contains(filter) || $0.code.lowercased().hasPrefix(filter) }.prefix(6))
        TextField("Digite um idioma…", text: $model.languageDraft)
          .textFieldStyle(.plain).inkStyle(InkType.rowCopy, color: Ink.primary)
          .padding(.horizontal, 13).padding(.vertical, 10)
          .glassField()
          .onSubmit { if let first = matches.first { model.pickLanguage(code: first.code, name: first.name) } }
        if !matches.isEmpty {
          VStack(spacing: 0) {
            ForEach(matches, id: \.code) { lang in
              Button {
                model.pickLanguage(code: lang.code, name: lang.name)
              } label: {
                HStack {
                  Text(lang.name).inkStyle(InkType.rowCopy, color: Ink.primary)
                  Spacer()
                  Text(lang.code).inkStyle(InkType.statusLabel, color: Ink.secondary)
                }
                .padding(.horizontal, 13).padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              if lang.code != matches.last?.code { GlassSeparator() }
            }
          }
          .glassCard(cornerRadius: PageGlass.chipRadius)
        }
      }
    }
    .frame(maxWidth: 340, alignment: .leading)
  }

  private var roleWidget: some View {
    VStack(alignment: .leading, spacing: 10) {
      FlowChips(
        items: ["Student", "Sales", "Consultant", "Founder", "Engineer", "Analyst", "Creator", "Other"],
        selectedItem: model.role
      ) { r in
        model.pickRole(r)
      }
      HStack(spacing: 8) {
        TextField("ou diga com suas próprias palavras…", text: $model.roleDraft)
          .textFieldStyle(.plain).inkStyle(InkType.rowCopy, color: Ink.primary)
          .padding(.horizontal, 13).padding(.vertical, 9)
          .glassField()
          .onSubmit { model.answerRoleText() }
        SBInkButton(title: "→", horizontalPadding: 15, verticalPadding: 9) { model.answerRoleText() }
          .accessibilityLabel("Continuar")
      }
      .frame(maxWidth: 360)
    }
  }

  // MARK: permissions (one at a time)

  /// Every branch here is chosen by `model.permissionPrimaryAction`, so what the
  /// row can do is a property of the permission state rather than of a layout —
  /// and every branch keeps an explicit way forward, with the consequence spelled out.
  private func permStepWidget(
    _ key: String, _ name: String, _ why: String, onContinue: @escaping () -> Void
  ) -> some View {
    let action = model.permissionPrimaryAction(key)
    return VStack(alignment: .leading, spacing: 10) {
      VStack(alignment: .leading, spacing: 3) {
        Text(name).inkStyle(InkType.rowCopy, color: Ink.primary)
        // Every sentence on this card wraps and none of them truncate. Three of four shipped cut off
        // mid-word in the source app before this modifier went on, and a permission whose reason is
        // half-visible is a permission people deny.
        Text(why).inkStyle(InkType.statusLabel, color: Ink.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      if action == .reopen {
        Text("\(name) está ativo, mas o macOS só o entrega a uma abertura nova. Me reabra e eu continuo daqui.")
          .inkStyle(InkType.statusLabel, color: Ink.secondary)
          .fixedSize(horizontal: false, vertical: true)
        Button {
          model.acceptPermissionRelaunch(key)
        } label: {
          Text("Reabrir o Omi").frame(maxWidth: .infinity)
        }
        .buttonStyle(InkButtonStyle(kind: .primary))
        // The escape, with the consequence spelled out — never gate a step on something macOS cannot
        // grant from a dialog. Same object as every other escape on this card: `skipLink`, so the way
        // past a permission always looks the same and never outranks the way through it.
        skipLink("Depois, \(name) fica desligado até você reabrir", action: onContinue)
      } else if action == .proceed {
        Button {
          onContinue()
        } label: {
          HStack(spacing: 6) {
            Text("✓  \(name) ligado")
            Spacer()
            Text("Continuar →")
          }
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(InkButtonStyle(kind: .primary))
        .keyboardShortcut(.defaultAction)
      } else {
        // Never `.disabled`: while macOS is being waited on, the button becomes
        // a re-check. A grant that lands after the poll gave up used to leave
        // the user staring at a dead "Waiting for macOS…" with nothing to press.
        //
        // Waiting reads as a *secondary* capsule rather than a dimmed primary one: a filled pill at
        // 40% ink is the shape of a disabled control, and this one is the opposite of disabled.
        Button {
          if action == .recheck { model.recheckPermission(key) } else { model.requestPerm(key) }
        } label: {
          Text(action == .recheck ? "Aguardando o macOS… verificar de novo" : "Permitir \(name)")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(InkButtonStyle(kind: action == .recheck ? .secondary : .primary))
        // The escape is a **link, not a capsule**. Two full-width pills stacked read as a choice
        // between equals, and this choice is not between equals: every permission on this card is
        // something Omi cannot work without, and the skip is the exit, not the alternative. The
        // capsule this replaces was itself a correction of a bare `.plain` caption that people
        // missed — so the link keeps what that correction was actually buying: an underline and a
        // pointing-hand cursor, so it still reads as pressable, and `skipLinkMinHeight` of target so
        // it is still comfortably hittable. Faint but unmistakable, which is the whole ask.
        skipLink("Pular por enquanto", action: onContinue)
      }
    }
    .frame(maxWidth: 380, alignment: .leading)
  }

  private func skipLink(_ title: String, action: @escaping () -> Void) -> some View {
    SBSkipLink(title: title, action: action)
  }

  @ViewBuilder private var filesWidget: some View {
    switch model.localFileProfileState {
    case .idle:
      permStepWidget(
        "full_disk_access", "Acesso Total ao Disco", "para eu citar seus arquivos, somente leitura, e tudo fica neste Mac"
      ) {
        model.answerFiles()
      }
    case .scanning:
      VStack(alignment: .leading, spacing: 10) {
        Text("Montando seu perfil local").inkStyle(InkType.rowCopy, color: Ink.primary)
        HStack(spacing: 8) {
          ProgressView().controlSize(.small)
          Text("Examinando seus projetos e arquivos recentes…")
            .inkStyle(InkType.statusLabel, color: Ink.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(maxWidth: 380, alignment: .leading)
    case .complete(let fileCount, let memoryCount, let deniedFolders):
      VStack(alignment: .leading, spacing: 10) {
        Text("Seu perfil local está pronto").inkStyle(InkType.rowCopy, color: Ink.primary)
        Text("\(fileCount.formatted()) arquivos indexados · \(memoryCount) memórias de perfil salvas")
          .inkStyle(InkType.statusLabel, color: Ink.secondary)
          .fixedSize(horizontal: false, vertical: true)
        if !deniedFolders.isEmpty {
          Text("Algumas pastas precisam de acesso depois: \(deniedFolders.joined(separator: ", "))")
            .inkStyle(InkType.statusLabel, color: Ink.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        if model.fdaState != .on {
          // Same contract as `permStepWidget`: waiting turns the button into a
          // re-check rather than disabling it, so a grant that lands after the
          // poll gave up is never unreachable.
          let fdaAction = model.permissionPrimaryAction("full_disk_access")
          Button(
            fdaAction == .recheck
              ? "Aguardando o Acesso Total ao Disco… verificar de novo" : "Permitir Acesso Total ao Disco"
          ) {
            if fdaAction == .recheck {
              model.recheckPermission("full_disk_access")
            } else {
              model.requestPerm("full_disk_access")
            }
          }
          // A capsule, not a run of caption type: this asks macOS for a permission, which is the
          // heaviest thing on this card after Continue. `.secondary` keeps Continue the one primary.
          .buttonStyle(InkButtonStyle(kind: .secondary))
        }
        SBInkButton(title: "Continuar", isDefaultAction: true) { model.finishFilesStep() }
      }
      .frame(maxWidth: 380, alignment: .leading)
    case .failed(let message):
      VStack(alignment: .leading, spacing: 10) {
        Text("Não consegui terminar de examinar seus arquivos").inkStyle(InkType.rowCopy, color: Ink.primary)
        Text(message).inkStyle(InkType.statusLabel, color: Ink.secondary)
          .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: 10) {
          SBInkButton(title: "Tentar de novo") { model.retryLocalFileScan() }
          // The way past a failed scan is the only thing on this card the user may actually want,
          // so it is a capsule beside Retry rather than caption type trailing it.
          Button("Continuar sem examinar") { model.finishFilesStep() }
            .buttonStyle(InkButtonStyle(kind: .secondary))
        }
      }
      .frame(maxWidth: 380, alignment: .leading)
    }
  }

  // MARK: agents + context connectors

  private var agentsWidget: some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(spacing: 0) {
        Button {
          showAIAssistants.toggle()
        } label: {
          HStack {
            Text("Assistentes de IA").inkStyle(InkType.rowCopy, color: Ink.primary)
            Spacer()
            Image(systemName: showAIAssistants ? "chevron.up" : "chevron.down")
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(Ink.secondary)
          }
          // **The row is the target, not the two glyphs on it.** A `.plain` button hit-tests its
          // rendered label, and a `Spacer` renders nothing — so without this the whole span between
          // the title and the chevron, which is most of the row, was dead. It looked like a
          // disclosure and behaved like one only if you happened to press the word.
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 12)
        if showAIAssistants {
          GlassSeparator()
          ForEach(Array(model.agentRows.enumerated()), id: \.element.id) { i, row in
            connectRow(id: row.id, row.name, row.detail, state: model.agentStates[row.id] ?? "idle") {
              model.connectAgent(row.id)
            }
            if i < model.agentRows.count - 1 { GlassSeparator() }
          }
        }
      }
      .padding(.horizontal, 14)
      .glassCard(cornerRadius: PageGlass.rowRadius)
      SBInkButton(title: "Continuar", isDefaultAction: true) { model.answerAgents() }
    }
    .frame(maxWidth: 380, alignment: .leading)
  }

  private var contextWidget: some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(spacing: 0) {
        ForEach(Array(model.contextRows.enumerated()), id: \.element.id) { i, row in
          connectRow(
            id: row.id,
            row.name,
            model.contextDetails[row.id] ?? row.detail,
            state: model.contextStates[row.id] ?? "idle"
          ) {
            connectContext(row.id)
          }
          if i < model.contextRows.count - 1 { GlassSeparator() }
        }
      }
      .padding(.horizontal, 14)
      .glassCard(cornerRadius: PageGlass.rowRadius)
    }
    .frame(maxWidth: 380, alignment: .leading)
  }

  private func connectContext(_ id: String) {
    switch SBOnboardingModel.contextConnectionRoute(for: id) {
    case .importConnector(let connectorID):
      selectedImportConnector = ImportConnector.all.first { $0.id == connectorID }
    case .direct:
      model.connectContext(id)
    }
  }

  private func refreshContextStates() {
    model.refreshContextStates()
    importConnectorStatusStore.refreshPersistedManualImportMetrics()
    for connectorID in ["chatgpt", "claude"] {
      guard
        let connector = ImportConnector.all.first(where: { $0.id == connectorID }),
        importConnectorStatusStore.snapshot(for: connector).isConnected
      else { continue }
      model.markContextImportConnected(connectorID)
    }
  }

  private func connectRow(id: String, _ name: String, _ detail: String, state: String, action: @escaping () -> Void)
    -> some View
  {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 12) {
        ConnectorBrandIcon(brand: model.connectorBrand(id), size: 26, cornerRadius: 7)
        VStack(alignment: .leading, spacing: 1) {
          Text(name).inkStyle(InkType.rowCopy, color: Ink.primary)
          Text(detail).inkStyle(InkType.statusLabel, color: Ink.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 8)
        connectTrailing(state, action: action)
      }
      // Once Claude Code is connected, surface the restart prompt/button so its
      // running sessions actually reload the new MCP config (#10205).
      if id == "claudeCode", state == "on" {
        ClaudeCodeRestartSubtitle()
      }
    }
    .padding(.vertical, 10)
  }

  @ViewBuilder
  private func connectTrailing(_ state: String, action: @escaping () -> Void) -> some View {
    // Every readout here is `secondary` — glass carries two rungs, so "checking…" and "not installed"
    // cannot sit a step below "✓ on"; they all read as subordinate to the connector's name, which is
    // `primary`. The actions are stadium capsules from the one button style, not 7 pt rounded rects.
    switch state {
    case "on": Text("✓ ligado").inkStyle(InkType.statusLabel, color: Ink.secondary).fixedSize()
    case "connecting": Text("…").inkStyle(InkType.statusLabel, color: Ink.secondary).fixedSize()
    case "checking": Text("verificando…").inkStyle(InkType.statusLabel, color: Ink.secondary).fixedSize()
    case "unavailable": Text("não instalado").inkStyle(InkType.statusLabel, color: Ink.secondary).fixedSize()
    case "error":
      Button("Tentar de novo", action: action)
        .buttonStyle(InkButtonStyle(kind: .secondary))
    default:
      // `.secondary`, and this is a hierarchy decision rather than a taste one. There are six
      // connector rows on the context card and one Continue under them; filled, the six read as six
      // primary actions and the step's actual proceed action is the seventh identical black pill —
      // a wall of ink on a card whose whole job is to feel optional. Outlined, "Connect" is still
      // plainly a button and Continue is the only filled thing on the card.
      Button(state == "needsSignIn" ? "Tentar de novo" : "Conectar", action: action)
        .buttonStyle(InkButtonStyle(kind: .secondary))
    }
  }

  // MARK: capture

  private var captureWidget: some View {
    VStack(spacing: 8) {
      Button {
        model.capture(SBOnboardingModel.defaultCaptureSelection)
      } label: {
        Text("Só reuniões").frame(maxWidth: .infinity)
      }
      .buttonStyle(InkButtonStyle(kind: .primary))
      .keyboardShortcut(.defaultAction)
      Button {
        model.capture(.always)
      } label: {
        Text("Sempre ligado").frame(maxWidth: .infinity)
      }
      .buttonStyle(InkButtonStyle(kind: .secondary))
    }
    .frame(maxWidth: 340, alignment: .leading)
  }

  private var referralWidget: some View {
    VStack(alignment: .leading, spacing: 14) {
      ReferralProgramView(showsIntroduction: false)

      SBInkButton(title: "Me leve ao Omi", isDefaultAction: true) {
        model.finishReferral()
      }
    }
    .frame(maxWidth: 380, alignment: .leading)
  }
}

/// Wrapping chip row where each chip hugs its content (no wide grid cells that
/// push short chips far apart).
private struct FlowChips: View {
  let items: [String]
  var selectedItem: String? = nil
  let onPick: (String) -> Void
  var body: some View {
    ChipFlowLayout(spacing: 8, lineSpacing: 8) {
      ForEach(items, id: \.self) { item in
        let isSelected = selectedItem == item
        Button {
          onPick(item)
        } label: {
          // Selected inverts the ladder the same way the primary button does — `Ink.primary` fill,
          // `Ink.surface` label — so a chosen chip and a chosen anything else are the same object.
          Text(item).inkStyle(InkType.rowCopy, color: isSelected ? Ink.surface : Ink.primary)
            .padding(.horizontal, 15).padding(.vertical, 8)
            .background(Capsule(style: .continuous).fill(isSelected ? Ink.primary : .clear))
            .overlay(Capsule(style: .continuous).strokeBorder(isSelected ? .clear : Ink.hairline, lineWidth: 1))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(InkReduceMotion.animation(.easeOut(duration: InkMotion.press)), value: isSelected)
      }
    }
    .frame(maxWidth: 380, alignment: .leading)
  }
}

/// Minimal left-to-right wrapping flow layout (content-hugging).
private struct ChipFlowLayout: Layout {
  var spacing: CGFloat = 8
  var lineSpacing: CGFloat = 8

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let maxWidth = proposal.width ?? 380
    var x: CGFloat = 0
    var y: CGFloat = 0
    var rowHeight: CGFloat = 0
    for sub in subviews {
      let size = sub.sizeThatFits(.unspecified)
      if x + size.width > maxWidth, x > 0 {
        x = 0
        y += rowHeight + lineSpacing
        rowHeight = 0
      }
      x += size.width + spacing
      rowHeight = max(rowHeight, size.height)
    }
    return CGSize(width: maxWidth, height: y + rowHeight)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    var x: CGFloat = bounds.minX
    var y: CGFloat = bounds.minY
    var rowHeight: CGFloat = 0
    for sub in subviews {
      let size = sub.sizeThatFits(.unspecified)
      if x + size.width > bounds.minX + bounds.width, x > bounds.minX {
        x = bounds.minX
        y += rowHeight + lineSpacing
        rowHeight = 0
      }
      sub.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
      x += size.width + spacing
      rowHeight = max(rowHeight, size.height)
    }
  }
}

/// The one way past a permission step.
///
/// Deliberately the quietest actionable thing on the card: `statusLabel` in `Ink.secondary` — never
/// `Ink.tertiary`, which measures under AA on glass and is banned on first-run surfaces — underlined
/// so it still reads as pressable rather than as a caption, and centred under the primary action so
/// it is where the eye already is. It never becomes a capsule: a capsule beside a capsule is a fork
/// in the road, and this is a side door.
///
/// A `View` rather than a `@ViewBuilder` method on `SBOnboardingView` for one reason: it owns
/// `didPushCursor`, and that state has to be *per link*. Hung off the parent it would be one flag
/// shared by every escape the flow draws.
private struct SBSkipLink: View {
  let title: String
  let action: () -> Void

  /// A hit target no smaller than this, whatever the type is set at. `statusLabel` is 12 pt, and 12 pt
  /// of glyph is not a control — the padding is what keeps the de-emphasis a *visual* one rather than
  /// a usability tax on the person who genuinely wants out.
  static let skipLinkMinHeight: CGFloat = 28

  /// `NSCursor` push/pop is a **stack**, so every push owes exactly one pop. SwiftUI does not deliver
  /// `onHover(false)` to a view that leaves the hierarchy, and pressing this link is precisely that
  /// case: `action()` advances the step and unmounts the card with the pointer still over it. Without
  /// the flag the pointing-hand outlives the view and rides along over the next step's controls.
  /// Same idiom, and the same reason, as `LiveTranscriptExpandTap`.
  @State private var didPushCursor = false

  private func setHovered(_ hovering: Bool) {
    if hovering, !didPushCursor {
      NSCursor.pointingHand.push()
      didPushCursor = true
    } else if !hovering, didPushCursor {
      NSCursor.pop()
      didPushCursor = false
    }
  }

  var body: some View {
    HStack {
      Spacer(minLength: 0)
      Button {
        // Pop before the step swaps this card away; `onDisappear` is the belt to this braces.
        setHovered(false)
        action()
      } label: {
        Text(title)
          .inkStyle(InkType.statusLabel, color: Ink.secondary)
          .underline()
          .fixedSize(horizontal: false, vertical: true)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 12)
          .frame(minHeight: Self.skipLinkMinHeight)
          // The label is the hit test, and a run of 12 pt type is a thin one. Without this the
          // padding above is decoration: SwiftUI hit-tests what `.plain` actually renders.
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .onHover { setHovered($0) }
      .onDisappear { setHovered(false) }
      Spacer(minLength: 0)
    }
  }
}
