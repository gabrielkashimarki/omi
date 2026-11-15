import OmiTheme
import SwiftUI

enum PushToTalkSettingsGuidance {
  static func lines(
    pttEnabled: Bool,
    doubleTapForLock: Bool,
    shortcutLabel: String
  ) -> [String] {
    guard pttEnabled else {
      return ["Ative Apertar para Falar para usar a entrada de voz."]
    }

    let hold = "Segure \(shortcutLabel) para falar e solte para enviar."
    let handsFree =
      doubleTapForLock
      ? "Toque duas vezes para continuar ouvindo sem usar as mãos; toque de novo para enviar."
      : "Ative o Toque Duplo para o Modo Travado para ouvir sem usar as mãos."
    return [hold, handsFree, "Diga “type…” para ditar no app em foco."]
  }
}

struct ShortcutsSettingsSection: View {
  @ObservedObject private var settings = ShortcutSettings.shared
  @Binding var highlightedSettingId: String?
  @State private var recordingTarget: ShortcutTarget?
  @State private var captureError: String?
  @State private var pendingModifierOnlyShortcut: ShortcutSettings.KeyboardShortcut?
  @State private var localShortcutCaptureMonitor: Any?

  init(highlightedSettingId: Binding<String?> = .constant(nil)) {
    self._highlightedSettingId = highlightedSettingId
  }

  private enum ShortcutTarget {
    case askOmi
    case pushToTalk
  }

  var body: some View {
    VStack(spacing: OmiSpacing.xl) {
      askOmiKeyCard
      pttKeyCard
      doubleTapCard
      pttSoundsCard
      muteAudioCard
    }
    .onAppear {
    }
    .onDisappear {
      stopShortcutCapture()
    }
  }

  private var askOmiKeyCard: some View {
    VStack(alignment: .leading, spacing: OmiSpacing.lg) {
      VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
        Text("Atalho de Abrir o Omi")
          .scaledFont(size: OmiType.subheading, weight: .semibold)
          .foregroundColor(Ink.primary)
        Text("Atalho global para abrir o app do Omi de qualquer lugar.")
          .scaledFont(size: OmiType.body)
          .foregroundColor(Ink.secondary)
      }

      HStack(spacing: OmiSpacing.md) {
        ForEach(ShortcutSettings.askOmiPresets, id: \.self) { shortcut in
          askOmiKeyButton(shortcut)
        }
        customShortcutButton(
          for: .askOmi, isSelected: settings.askOmiEnabled && settings.askOmiUsesCustomShortcut)
        disableShortcutButton(isDisabled: !settings.askOmiEnabled) {
          stopShortcutCapture()
          settings.askOmiEnabled = false
        }
        Spacer()
      }

      if settings.askOmiEnabled
        && (recordingTarget == .askOmi || settings.askOmiUsesCustomShortcut
          || (captureError != nil && recordingTarget == .askOmi))
      {
        shortcutRecorderCard(
          title: recordingTarget == .askOmi
            ? "Aperte agora seu atalho personalizado de Abrir o Omi" : "Atalho personalizado de Abrir o Omi",
          shortcut: settings.askOmiShortcut,
          isRecording: recordingTarget == .askOmi,
          action: { startShortcutCapture(.askOmi) },
          helperText: "Use pelo menos uma tecla que não seja modificadora."
        )
      }
    }
    .padding(OmiSpacing.xl)
    .background(
      RoundedRectangle(cornerRadius: SettingsGlassMetrics.cardRadius, style: .continuous)
        .fill(Ink.rowFill)
    )
    .modifier(
      SettingHighlightModifier(
        settingId: "floatingbar.shortcut", highlightedSettingId: $highlightedSettingId))
  }

  private func askOmiKeyButton(_ shortcut: ShortcutSettings.KeyboardShortcut) -> some View {
    let isSelected =
      settings.askOmiEnabled && settings.askOmiShortcut == shortcut
      && !settings.askOmiUsesCustomShortcut
    return Button {
      stopShortcutCapture()
      settings.updateAskOmiRegistration(enabled: true, shortcut: shortcut)
    } label: {
      shortcutSelectionLabel(tokens: shortcut.displayTokens, isSelected: isSelected)
    }
    .buttonStyle(.plain)
  }

  private var pttKeyCard: some View {
    VStack(alignment: .leading, spacing: OmiSpacing.lg) {
      VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
        Text("Apertar para Falar")
          .scaledFont(size: OmiType.subheading, weight: .semibold)
          .foregroundColor(Ink.primary)
        Text("Segure a tecla para falar e solte para enviar sua pergunta à IA.")
          .scaledFont(size: OmiType.body)
          .foregroundColor(Ink.secondary)
      }

      HStack(spacing: OmiSpacing.md) {
        ForEach(ShortcutSettings.pttPresets, id: \.self) { shortcut in
          pttKeyButton(shortcut)
        }
        customShortcutButton(
          for: .pushToTalk, isSelected: settings.pttEnabled && settings.pttUsesCustomShortcut)
        disableShortcutButton(isDisabled: !settings.pttEnabled) {
          stopShortcutCapture()
          settings.pttEnabled = false
        }
        Spacer()
      }

      if settings.pttEnabled
        && (recordingTarget == .pushToTalk || settings.pttUsesCustomShortcut
          || (captureError != nil && recordingTarget == .pushToTalk))
      {
        shortcutRecorderCard(
          title: recordingTarget == .pushToTalk
            ? "Aperte agora seu atalho personalizado de apertar para falar" : "Atalho personalizado de apertar para falar",
          shortcut: settings.pttShortcut,
          isRecording: recordingTarget == .pushToTalk,
          action: { startShortcutCapture(.pushToTalk) },
          helperText: "Use uma tecla modificadora ou uma combinação de teclas."
        )
      }

      VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
        ForEach(
          PushToTalkSettingsGuidance.lines(
            pttEnabled: settings.pttEnabled,
            doubleTapForLock: settings.doubleTapForLock,
            shortcutLabel: settings.pttShortcut.displayLabel
          ),
          id: \.self
        ) { line in
          Text(line)
            .scaledFont(size: OmiType.caption)
            .foregroundColor(Ink.secondary)
        }
      }
    }
    .padding(OmiSpacing.xl)
    .background(
      RoundedRectangle(cornerRadius: SettingsGlassMetrics.cardRadius, style: .continuous)
        .fill(Ink.rowFill)
    )
    .modifier(
      SettingHighlightModifier(
        settingId: "floatingbar.ptt", highlightedSettingId: $highlightedSettingId))
  }

  private func pttKeyButton(_ shortcut: ShortcutSettings.KeyboardShortcut) -> some View {
    let isSelected =
      settings.pttEnabled && settings.pttShortcut == shortcut && !settings.pttUsesCustomShortcut
    return Button {
      stopShortcutCapture()
      settings.pttEnabled = true
      settings.pttShortcut = shortcut
    } label: {
      shortcutSelectionLabel(tokens: shortcut.displayTokens, isSelected: isSelected)
    }
    .buttonStyle(.plain)
  }

  private var doubleTapCard: some View {
    HStack(spacing: OmiSpacing.lg) {
      VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
        Text("Toque Duplo para o Modo Travado")
          .scaledFont(size: OmiType.subheading, weight: .semibold)
          .foregroundColor(Ink.primary)
        Text(
          settings.doubleTapForLock
            ? "Toque duas vezes na tecla de apertar para falar para continuar ouvindo sem usar as mãos. Toque de novo para enviar."
            : "Ative para continuar ouvindo sem usar as mãos com um toque duplo."
        )
        .scaledFont(size: OmiType.body)
        .foregroundColor(Ink.secondary)
      }
      Spacer()
      Toggle("", isOn: $settings.doubleTapForLock)
        .toggleStyle(OmiToggleStyle())
    }
    .padding(OmiSpacing.xl)
    .background(
      RoundedRectangle(cornerRadius: SettingsGlassMetrics.cardRadius, style: .continuous)
        .fill(Ink.rowFill)
    )
    .opacity(settings.pttEnabled ? 1 : 0.55)
    .disabled(!settings.pttEnabled)
    .modifier(
      SettingHighlightModifier(
        settingId: "floatingbar.doubletap", highlightedSettingId: $highlightedSettingId))
  }

  private var pttSoundsCard: some View {
    HStack(spacing: OmiSpacing.lg) {
      VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
        Text("Sons de Apertar para Falar")
          .scaledFont(size: OmiType.subheading, weight: .semibold)
          .foregroundColor(Ink.primary)
        Text("Toca um som ao iniciar e terminar a entrada de voz.")
          .scaledFont(size: OmiType.body)
          .foregroundColor(Ink.secondary)
      }
      Spacer()
      Toggle("", isOn: $settings.pttSoundsEnabled)
        .toggleStyle(OmiToggleStyle())
    }
    .padding(OmiSpacing.xl)
    .background(
      RoundedRectangle(cornerRadius: SettingsGlassMetrics.cardRadius, style: .continuous)
        .fill(Ink.rowFill)
    )
    .opacity(settings.pttEnabled ? 1 : 0.55)
    .disabled(!settings.pttEnabled)
    .modifier(
      SettingHighlightModifier(
        settingId: "floatingbar.pttsounds", highlightedSettingId: $highlightedSettingId))
  }

  private var muteAudioCard: some View {
    HStack(spacing: OmiSpacing.lg) {
      VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
        Text("Silenciar o Áudio Enquanto Fala")
          .scaledFont(size: OmiType.subheading, weight: .semibold)
          .foregroundColor(Ink.primary)
        Text("Silencia música e outras reproduções enquanto você segura apertar para falar e restaura ao soltar.")
          .scaledFont(size: OmiType.body)
          .foregroundColor(Ink.secondary)
      }
      Spacer()
      Toggle("", isOn: $settings.pttMuteSystemAudio)
        .toggleStyle(OmiToggleStyle())
    }
    .padding(OmiSpacing.xl)
    .background(
      RoundedRectangle(cornerRadius: SettingsGlassMetrics.cardRadius, style: .continuous)
        .fill(Ink.rowFill)
    )
    .opacity(settings.pttEnabled ? 1 : 0.55)
    .disabled(!settings.pttEnabled)
    .modifier(
      SettingHighlightModifier(
        settingId: "floatingbar.muteaudio", highlightedSettingId: $highlightedSettingId))
  }

  private var referenceCard: some View {
    VStack(alignment: .leading, spacing: OmiSpacing.md) {
      Text("Atalhos de Teclado")
        .scaledFont(size: OmiType.subheading, weight: .semibold)
        .foregroundColor(Ink.primary)

      shortcutRow(
        label: "Abrir o Omi",
        keys: settings.askOmiEnabled ? settings.askOmiShortcut.displayLabel : "Desativado")
      shortcutRow(label: "Alternar barra flutuante", keys: "\u{2318}\\")
      shortcutRow(
        label: "Apertar para falar",
        keys: settings.pttEnabled ? settings.pttShortcut.displayLabel + " segurando" : "Desativado")
      if settings.pttEnabled && settings.doubleTapForLock {
        shortcutRow(
          label: "Escuta travada", keys: settings.pttShortcut.displayLabel + " \u{00D7}2")
      }
    }
    .padding(OmiSpacing.xl)
    .background(
      RoundedRectangle(cornerRadius: SettingsGlassMetrics.cardRadius, style: .continuous)
        .fill(Ink.rowFill)
    )
  }

  private func shortcutRow(label: String, keys: String) -> some View {
    HStack {
      Text(label)
        .scaledFont(size: OmiType.body)
        .foregroundColor(Ink.secondary)
      Spacer()
      Text(keys)
        .scaledMonospacedFont(size: 14, weight: .medium)
        .foregroundColor(Ink.primary)
        .padding(.horizontal, OmiSpacing.sm)
        .padding(.vertical, OmiSpacing.xxs)
        .background(Ink.rowFill)
        .cornerRadius(SettingsGlassMetrics.pillRadius)
    }
  }

  private func customShortcutButton(for target: ShortcutTarget, isSelected: Bool) -> some View {
    Button {
      switch target {
      case .askOmi:
        settings.askOmiEnabled = true
      case .pushToTalk:
        settings.pttEnabled = true
      }
      startShortcutCapture(target)
    } label: {
      Text("Personalizado")
        .scaledFont(size: OmiType.body, weight: .medium)
        .foregroundColor(Ink.primary)
        .padding(.horizontal, OmiSpacing.md)
        .padding(.vertical, OmiSpacing.sm)
        .background(
          RoundedRectangle(cornerRadius: SettingsGlassMetrics.cardRadius, style: .continuous)
            .fill(SettingsSelection.optionFill(isSelected: isSelected || recordingTarget == target))
        )
        .overlay(
          RoundedRectangle(cornerRadius: SettingsGlassMetrics.cardRadius, style: .continuous)
            .stroke(
              isSelected || recordingTarget == target
                ? SettingsSelection.optionStroke(isSelected: true) : Color.clear,
              lineWidth: 2)
        )
    }
    .buttonStyle(.plain)
  }

  private func disableShortcutButton(isDisabled: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text("Desativar")
        .scaledFont(size: OmiType.body, weight: .medium)
        .foregroundColor(Ink.primary)
        .padding(.horizontal, OmiSpacing.md)
        .padding(.vertical, OmiSpacing.sm)
        .background(
          RoundedRectangle(cornerRadius: SettingsGlassMetrics.cardRadius, style: .continuous)
            .fill(SettingsSelection.optionFill(isSelected: isDisabled))
        )
        .overlay(
          RoundedRectangle(cornerRadius: SettingsGlassMetrics.cardRadius, style: .continuous)
            .stroke(isDisabled ? SettingsSelection.optionStroke(isSelected: true) : Color.clear, lineWidth: 2)
        )
    }
    .buttonStyle(.plain)
  }

  private func shortcutSelectionLabel(tokens: [String], isSelected: Bool) -> some View {
    HStack(spacing: OmiSpacing.xs) {
      ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
        Text(token)
          .scaledFont(size: OmiType.body, weight: .medium)
      }
    }
    .foregroundColor(Ink.primary)
    .padding(.horizontal, OmiSpacing.md)
    .padding(.vertical, OmiSpacing.sm)
    .background(
      RoundedRectangle(cornerRadius: SettingsGlassMetrics.cardRadius, style: .continuous)
        .fill(SettingsSelection.optionFill(isSelected: isSelected))
    )
    .overlay(
      RoundedRectangle(cornerRadius: SettingsGlassMetrics.cardRadius, style: .continuous)
        .stroke(isSelected ? SettingsSelection.optionStroke(isSelected: true) : Color.clear, lineWidth: 2)
    )
  }

  private func shortcutRecorderCard(
    title: String,
    shortcut: ShortcutSettings.KeyboardShortcut,
    isRecording: Bool,
    action: @escaping () -> Void,
    helperText: String
  ) -> some View {
    VStack(alignment: .leading, spacing: OmiSpacing.sm) {
      Text(title)
        .scaledFont(size: OmiType.body, weight: .semibold)
        .foregroundColor(Ink.primary)

      HStack(spacing: OmiSpacing.sm) {
        HStack(spacing: OmiSpacing.xs) {
          ForEach(Array(shortcut.displayTokens.enumerated()), id: \.offset) { _, token in
            Text(token)
              .scaledFont(size: OmiType.body, weight: .semibold)
              .foregroundColor(Ink.primary)
              .padding(.horizontal, token.count > 2 ? 10 : 8)
              .padding(.vertical, OmiSpacing.xs)
              .background(
                RoundedRectangle(cornerRadius: SettingsGlassMetrics.controlRadius, style: .continuous)
                  .fill(Ink.wash)
              )
          }
        }

        Spacer()

        Button(action: action) {
          Text(isRecording ? "Ouvindo…" : "Salvar")
        }
        .buttonStyle(OmiButtonStyle(.primary, size: .compact))
      }

      Text(helperText)
        .scaledFont(size: OmiType.caption)
        .foregroundColor(Ink.secondary)

      if let captureError, isRecording {
        Text(captureError)
          .scaledFont(size: OmiType.caption, weight: .medium)
          .foregroundColor(Ink.errorRed)
      }
    }
    .padding(OmiSpacing.md)
    .background(
      RoundedRectangle(cornerRadius: SettingsGlassMetrics.cardRadius, style: .continuous)
        .fill(Ink.wash)
    )
  }

  private func startShortcutCapture(_ target: ShortcutTarget) {
    stopShortcutCapture()
    recordingTarget = target
    captureError = nil
    pendingModifierOnlyShortcut = nil

    localShortcutCaptureMonitor = NSEvent.addLocalMonitorForEvents(matching: [
      .flagsChanged, .keyDown,
    ]) { event in
      handleShortcutCapture(event) ? nil : event
    }
  }

  private func stopShortcutCapture() {
    if let monitor = localShortcutCaptureMonitor {
      NSEvent.removeMonitor(monitor)
      localShortcutCaptureMonitor = nil
    }
    recordingTarget = nil
    captureError = nil
    pendingModifierOnlyShortcut = nil
  }

  private func handleShortcutCapture(_ event: NSEvent) -> Bool {
    guard let target = recordingTarget else { return false }

    switch target {
    case .askOmi:
      if event.type == .flagsChanged {
        captureError = "Abrir o Omi precisa de uma tecla que não seja modificadora."
        return true
      }
      guard
        let shortcut = ShortcutSettings.KeyboardShortcut.fromRecordingEvent(
          event, allowModifierOnly: false)
      else {
        return false
      }
      settings.updateAskOmiRegistration(enabled: true, shortcut: shortcut)
    case .pushToTalk:
      if event.type == .flagsChanged {
        let activeModifiers = ShortcutSettings.KeyboardShortcut.normalizedModifiers(event.modifierFlags)
        if activeModifiers.isEmpty {
          guard let shortcut = pendingModifierOnlyShortcut else { return true }
          settings.pttEnabled = true
          settings.pttShortcut = shortcut
          stopShortcutCapture()
          return true
        }
        pendingModifierOnlyShortcut = ShortcutSettings.KeyboardShortcut.fromRecordingEvent(
          event,
          allowModifierOnly: true
        )
        return true
      }
      guard
        let shortcut = ShortcutSettings.KeyboardShortcut.fromRecordingEvent(
          event, allowModifierOnly: true)
      else {
        return false
      }
      guard ShortcutSettings.isSafePushToTalkShortcut(shortcut) else {
        captureError = "Apertar para falar precisa de uma tecla modificadora para que a digitação normal não inicie uma fala."
        return true
      }
      pendingModifierOnlyShortcut = nil
      settings.pttEnabled = true
      settings.pttShortcut = shortcut
    }

    stopShortcutCapture()
    return true
  }
}
