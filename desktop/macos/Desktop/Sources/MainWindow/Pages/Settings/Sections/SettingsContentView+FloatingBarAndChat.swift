import OmiTheme
import Sparkle
import SwiftUI
import UniformTypeIdentifiers
import WebKit

extension SettingsContentView {
  var floatingBarSection: some View {
    VStack(spacing: OmiSpacing.xl) {
      settingsCard(settingId: "floatingbar.show") {
        HStack(spacing: OmiSpacing.lg) {
          Text("Mostrar barra flutuante")
            .scaledFont(size: OmiType.subheading, weight: .semibold)
            .foregroundColor(Ink.primary)

          Spacer()

          Toggle("", isOn: $showAskOmiBar)
            .toggleStyle(OmiToggleStyle())
            .labelsHidden()
            .onChange(of: showAskOmiBar) { _, newValue in
              // A change that merely mirrors the preference (arriving via
              // `.floatingBarEnabledDidChange`) is already applied; only a user flip acts.
              guard newValue != FloatingControlBarManager.shared.isEnabled else { return }
              if newValue {
                FloatingControlBarManager.shared.show()
              } else {
                FloatingControlBarManager.shared.hide()
              }
            }
        }
      }

      // HIDDEN DELIBERATELY (Nik, 2026-08-25): Notification Previews, Background Style, and
      // Draggable Floating Bar are intentionally not rendered (their stored settings still
      // apply). Product direction, not dead code — do not re-wire without asking Nik.
      // settingsCard(settingId: "floatingbar.notificationpreviews") {
      // HStack(spacing: OmiSpacing.lg) {
      // VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
      // Text("Notification Previews")
      // .scaledFont(size: OmiType.subheading, weight: .semibold)
      // .foregroundColor(Ink.primary)
      // Text(
      // "Show assistant notifications under the Floating Bar. When off, notifications use macOS banners instead."
      // )
      // .scaledFont(size: OmiType.body)
      // .foregroundColor(Ink.secondary)
      // }
      // Spacer()
      // Toggle("", isOn: $shortcutSettings.floatingBarNotificationPreviewsEnabled)
      // .toggleStyle(OmiToggleStyle())
      // }
      // }

      // settingsCard(settingId: "floatingbar.background") {
      // VStack(alignment: .leading, spacing: OmiSpacing.lg) {
      // Text("Background Style")
      // .scaledFont(size: OmiType.subheading, weight: .semibold)
      // .foregroundColor(Ink.primary)
      //
      // HStack(spacing: OmiSpacing.lg) {
      // Text("Transparent")
      // .scaledFont(size: OmiType.body, weight: shortcutSettings.solidBackground ? .regular : .semibold)
      // .foregroundColor(
      // shortcutSettings.solidBackground ? Ink.secondary : Ink.primary)
      //
      // Toggle("", isOn: $shortcutSettings.solidBackground)
      // .toggleStyle(OmiToggleStyle())
      // .labelsHidden()
      //
      // Text("Solid Dark")
      // .scaledFont(size: OmiType.body, weight: shortcutSettings.solidBackground ? .semibold : .regular)
      // .foregroundColor(
      // shortcutSettings.solidBackground ? Ink.primary : Ink.secondary)
      //
      // Spacer()
      // }
      // }
      // }

      // settingsCard(settingId: "floatingbar.draggable") {
      // HStack(spacing: OmiSpacing.lg) {
      // VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
      // Text("Draggable Floating Bar")
      // .scaledFont(size: OmiType.subheading, weight: .semibold)
      // .foregroundColor(Ink.primary)
      // Text("Allow repositioning the floating bar by dragging it.")
      // .scaledFont(size: OmiType.body)
      // .foregroundColor(Ink.secondary)
      // }
      // Spacer()
      // Toggle("", isOn: $shortcutSettings.draggableBarEnabled)
      // .toggleStyle(OmiToggleStyle())
      // }
      // }

      settingsCard(settingId: "floatingbar.typedvoiceanswers") {
        HStack(spacing: OmiSpacing.lg) {
          VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
            Text("Perguntas Digitadas")
              .scaledFont(size: OmiType.subheading, weight: .semibold)
              .foregroundColor(Ink.primary)
            Text("Fala as respostas em voz alta quando você envia uma pergunta digitada pela barra flutuante.")
              .scaledFont(size: OmiType.body)
              .foregroundColor(Ink.secondary)
          }
          Spacer()
          Toggle("", isOn: floatingBarTypedVoiceAnswersBinding)
            .toggleStyle(OmiToggleStyle())
        }
      }

      settingsCard(settingId: "floatingbar.screenshare") {
        HStack(spacing: OmiSpacing.lg) {
          VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
            Text("Compartilhar Tela no Chat")
              .scaledFont(size: OmiType.subheading, weight: .semibold)
              .foregroundColor(Ink.primary)
            Text("Deixa o Perguntar ao Omi capturar sua tela quando você pergunta sobre o que está nela.")
              .scaledFont(size: OmiType.body)
              .foregroundColor(Ink.secondary)
          }
          Spacer()
          Toggle("", isOn: $chatScreenshotSharingEnabled)
            .toggleStyle(OmiToggleStyle())
            .labelsHidden()
        }
      }

      // Push-to-talk replies are always spoken, so `hasAnyFloatingBarVoiceAnswersEnabled` is a
      // constant and these two never dimmed. A greyed, unresponsive control is how the rest of
      // this pane says "the thing behind this is off" — spending that signal on a state no
      // setting can reach makes a live control read as dead.
      assistantVoicePicker(settingId: "floatingbar.voice")

      voiceSpeedSlider(settingId: "floatingbar.voicespeed")
    }
  }

  var shortcutsSection: some View {
    ShortcutsSettingsSection(highlightedSettingId: $highlightedSettingId)
  }

  /// Claude's account state under the AI Provider picker. Without the Connect
  /// button, a signed-out Claude chat pointed the user here with no way to sign in.
  @ViewBuilder
  var claudeConnectionRow: some View {
    if chatProvider?.isClaudeConnected == true {
      HStack {
        Image(systemName: "checkmark.circle.fill")
          .foregroundColor(Ink.listeningGreen)
          .scaledFont(size: OmiType.caption)
        Text("Conectado ao Claude")
          .scaledFont(size: OmiType.caption)
          .foregroundColor(Ink.secondary)

        Spacer()

        Button("Desconectar") {
          Task {
            await chatProvider?.disconnectClaude()
          }
        }
        .buttonStyle(.plain)
        .scaledFont(size: OmiType.caption, weight: .medium)
        .foregroundColor(Ink.errorRed)
      }
    } else {
      HStack {
        Image(systemName: "person.badge.key")
          .foregroundColor(Ink.secondary)
          .scaledFont(size: OmiType.caption)
        Text("Não conectado ao Claude")
          .scaledFont(size: OmiType.caption)
          .foregroundColor(Ink.secondary)

        Spacer()

        Button("Conectar Claude") {
          Task {
            await chatProvider?.connectClaude()
          }
        }
        .buttonStyle(OmiButtonStyle(.primary, size: .compact))
      }
    }
  }

  var aiChatSection: some View {
    VStack(spacing: OmiSpacing.xl) {
      // AI Provider card
      settingsCard(settingId: "aichat.provider") {
        VStack(alignment: .leading, spacing: OmiSpacing.md) {
          HStack {
            Image(systemName: "cpu")
              .scaledFont(size: OmiType.subheading)
              .foregroundColor(Ink.secondary)

            Text("Provedor de IA")
              .scaledFont(size: OmiType.subheading, weight: .semibold)
              .foregroundColor(Ink.primary)

            Spacer()

            SettingsMenuPicker(selection: $chatBridgeMode) {
              ForEach(AIProvider.all) { provider in
                Text(provider.displayName).tag(provider.bridgeModeRawValue)
              }
            }
            .onChange(of: chatBridgeMode) { _, newMode in
              if let mode = ChatProvider.BridgeMode(rawValue: newMode) {
                Task {
                  await chatProvider?.switchBridgeMode(to: mode)
                }
              }
            }
          }

          if let provider = AIProvider.from(bridgeMode: chatBridgeMode) {
            if let url = provider.attributionURL {
              Link(destination: url) {
                Text("\(provider.tagline) · \(url.host ?? "")")
                  .scaledFont(size: OmiType.caption)
                  .foregroundColor(Ink.secondary)
              }
            } else {
              Text(provider.tagline)
                .scaledFont(size: OmiType.caption)
                .foregroundColor(Ink.secondary)
            }
          }

          if chatBridgeMode == "claudeCode" {
            GlassSeparator()
            claudeConnectionRow
          }
        }
      }
      .onAppear {
        chatProvider?.checkClaudeConnectionStatus()
      }

      // Ask Mode card
      settingsCard(settingId: "aichat.askmode") {
        VStack(alignment: .leading, spacing: OmiSpacing.md) {
          HStack {
            Image(systemName: "bubble.left.and.bubble.right")
              .scaledFont(size: OmiType.subheading)
              .foregroundColor(Ink.secondary)

            Text("Modo Perguntar")
              .scaledFont(size: OmiType.subheading, weight: .semibold)
              .foregroundColor(Ink.primary)

            Spacer()

            Toggle("", isOn: $askModeEnabled)
              .toggleStyle(OmiToggleStyle())
              .controlSize(.small)
              .labelsHidden()
          }

          Text(
            "Quando ativado, mostra um seletor Perguntar/Agir no chat. O modo Perguntar limita a IA a ações somente de leitura. Quando desativado, a IA sempre roda no modo Agir."
          )
          .scaledFont(size: OmiType.caption)
          .foregroundColor(Ink.secondary)
        }
      }

      // Workspace card
      settingsCard(settingId: "aichat.workspace") {
        VStack(alignment: .leading, spacing: OmiSpacing.md) {
          HStack {
            Image(systemName: "folder")
              .scaledFont(size: OmiType.subheading)
              .foregroundColor(Ink.secondary)

            Text("Espaço de Trabalho")
              .scaledFont(size: OmiType.subheading, weight: .semibold)
              .foregroundColor(Ink.primary)

            Spacer()

            Button("Procurar…") {
              let panel = NSOpenPanel()
              panel.canChooseFiles = false
              panel.canChooseDirectories = true
              panel.allowsMultipleSelection = false
              panel.message = "Selecione uma pasta de projeto"
              if panel.runModal() == .OK, let url = panel.url {
                aiChatWorkingDirectory = url.path
                // `ChatProvider` holds its own `@AppStorage` wrapper over the same key, and a
                // wrapper's `didSet` only fires for writes made through that wrapper — so the
                // provider has to be written to directly for it to reconfigure the runtime.
                chatProvider?.aiChatWorkingDirectory = url.path
                // Unconditional. The old `== nil` guard meant choosing a *second* workspace left
                // the agent's file-system root on the first one, so the next provider switch
                // (`effectiveAgentWorkingDirectory()`) handed the runtime the abandoned project.
                chatProvider?.workingDirectory = url.path
                Task { await rediscoverAIChatConfig() }
              }
            }
            .buttonStyle(OmiButtonStyle(.primary, size: .compact))

            if !aiChatWorkingDirectory.isEmpty {
              Button("Limpar") {
                aiChatWorkingDirectory = ""
                chatProvider?.aiChatWorkingDirectory = ""
                chatProvider?.workingDirectory = nil
                Task { await rediscoverAIChatConfig() }
              }
              .buttonStyle(OmiButtonStyle(.primary, size: .compact))
            }
          }

          if !aiChatWorkingDirectory.isEmpty {
            Text(aiChatWorkingDirectory)
              .scaledFont(size: OmiType.caption)
              .foregroundColor(Ink.secondary)
              .lineLimit(1)
              .truncationMode(.middle)

            Text("O CLAUDE.md e as skills do projeto serão descobertos a partir desta pasta")
              .scaledFont(size: OmiType.caption)
              .foregroundColor(Ink.secondary)
          } else {
            Text(
              "Nenhum espaço de trabalho definido. Defina uma pasta de projeto para descobrir o CLAUDE.md e as skills do projeto."
            )
            .scaledFont(size: OmiType.caption)
            .foregroundColor(Ink.secondary)
          }
        }
      }

      // CLAUDE.md card
      settingsCard(settingId: "aichat.claudemd") {
        VStack(alignment: .leading, spacing: OmiSpacing.md) {
          HStack {
            Image(systemName: "doc.text")
              .scaledFont(size: OmiType.subheading)
              .foregroundColor(Ink.secondary)

            Text("CLAUDE.md")
              .scaledFont(size: OmiType.subheading, weight: .semibold)
              .foregroundColor(Ink.primary)

            Spacer()
          }

          Text("Apenas referência: o conteúdo do CLAUDE.md nunca é injetado nas instruções do chat.")
            .scaledFont(size: OmiType.caption)
            .foregroundColor(Ink.secondary)

          // Global CLAUDE.md
          VStack(alignment: .leading, spacing: OmiSpacing.sm) {
            HStack {
              Text("Global")
                .scaledFont(size: OmiType.caption, weight: .medium)
                .foregroundColor(Ink.secondary)
                .padding(.horizontal, OmiSpacing.xs)
                .padding(.vertical, OmiSpacing.hairline)
                .background(
                  RoundedRectangle(cornerRadius: OmiChrome.stripRadius, style: .continuous)
                    .fill(Ink.wash)
                )

              Spacer()

              if aiChatClaudeMdContent != nil {
                Button("Ver") {
                  fileViewerTitle = "CLAUDE.md global"
                  fileViewerContent = aiChatClaudeMdContent ?? ""
                  showFileViewer = true
                }
                .buttonStyle(OmiButtonStyle(.primary, size: .compact))
              }
            }

            if let path = aiChatClaudeMdPath, let content = aiChatClaudeMdContent {
              let sizeKB = Double(content.utf8.count) / 1024.0
              Text("\(path) (\(String(format: "%.1f", sizeKB)) KB)")
                .scaledFont(size: OmiType.caption)
                .foregroundColor(Ink.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            } else {
              Text("Nenhum CLAUDE.md encontrado em ~/.claude/CLAUDE.md")
                .scaledFont(size: OmiType.caption)
                .foregroundColor(Ink.secondary)
            }
          }

          // Project CLAUDE.md (only show if workspace is set)
          if !aiChatWorkingDirectory.isEmpty {
            GlassSeparator()

            VStack(alignment: .leading, spacing: OmiSpacing.sm) {
              HStack {
                Text("Projeto")
                  .scaledFont(size: OmiType.caption, weight: .medium)
                  .foregroundColor(Ink.secondary)
                  .padding(.horizontal, OmiSpacing.xs)
                  .padding(.vertical, OmiSpacing.hairline)
                  .background(
                    RoundedRectangle(cornerRadius: OmiChrome.stripRadius, style: .continuous)
                      .fill(Ink.rowFill)
                  )

                Spacer()

                if aiChatProjectClaudeMdContent != nil {
                  Button("Ver") {
                    fileViewerTitle = "CLAUDE.md do projeto"
                    fileViewerContent = aiChatProjectClaudeMdContent ?? ""
                    showFileViewer = true
                  }
                  .buttonStyle(OmiButtonStyle(.primary, size: .compact))
                }
              }

              if let path = aiChatProjectClaudeMdPath, let content = aiChatProjectClaudeMdContent {
                let sizeKB = Double(content.utf8.count) / 1024.0
                Text("\(path) (\(String(format: "%.1f", sizeKB)) KB)")
                  .scaledFont(size: OmiType.caption)
                  .foregroundColor(Ink.secondary)
                  .lineLimit(1)
                  .truncationMode(.middle)
              } else {
                Text("Nenhum CLAUDE.md encontrado em \(aiChatWorkingDirectory)/CLAUDE.md")
                  .scaledFont(size: OmiType.caption)
                  .foregroundColor(Ink.secondary)
              }
            }
          }
        }
      }

      // Skills card
      settingsCard(settingId: "aichat.skills") {
        VStack(alignment: .leading, spacing: OmiSpacing.md) {
          HStack {
            Image(systemName: "sparkles")
              .scaledFont(size: OmiType.subheading)
              .foregroundColor(Ink.secondary)

            if aiChatProjectDiscoveredSkills.isEmpty {
              Text("Skills (\(aiChatDiscoveredSkills.count) encontradas)")
                .scaledFont(size: OmiType.subheading, weight: .semibold)
                .foregroundColor(Ink.primary)
            } else {
              Text(
                "Skills (\(aiChatDiscoveredSkills.count) globais + \(aiChatProjectDiscoveredSkills.count) do projeto)"
              )
              .scaledFont(size: OmiType.subheading, weight: .semibold)
              .foregroundColor(Ink.primary)
            }

            Spacer()

            Button(action: { Task { await rediscoverAIChatConfig() } }) {
              Image(systemName: "arrow.clockwise")
                .scaledFont(size: OmiType.body)
            }
            .buttonStyle(OmiButtonStyle(.primary, size: .compact))
          }

          let allSkills: [(skill: (name: String, description: String, path: String), origin: String)] =
            aiChatDiscoveredSkills.map { ($0, "Global") }
            + aiChatProjectDiscoveredSkills.map { ($0, "Project") }

          if allSkills.isEmpty {
            Text("Nenhuma skill encontrada em ~/.claude/skills/")
              .scaledFont(size: OmiType.caption)
              .foregroundColor(Ink.secondary)
          } else {
            Text("As descrições das skills são incluídas no prompt de sistema do chat com IA")
              .scaledFont(size: OmiType.caption)
              .foregroundColor(Ink.secondary)

            // Search field
            HStack(spacing: OmiSpacing.sm) {
              Image(systemName: "magnifyingglass")
                .scaledFont(size: OmiType.caption)
                .foregroundColor(Ink.secondary)

              TextField("Buscar skills…", text: $skillSearchQuery)
                .textFieldStyle(.plain)
                .scaledFont(size: OmiType.body)
                .foregroundColor(Ink.primary)

              if !skillSearchQuery.isEmpty {
                ClearFieldButton { skillSearchQuery = "" }
              }
            }
            .padding(OmiSpacing.sm)
            .background(
              RoundedRectangle(cornerRadius: SettingsGlassMetrics.controlRadius, style: .continuous)
                .fill(Ink.wash)
            )

            ScrollView {
              let filteredSkills = allSkills.enumerated().filter { _, item in
                skillSearchQuery.isEmpty
                  || item.skill.name.localizedStandardContains(skillSearchQuery)
                  || item.skill.description.localizedStandardContains(skillSearchQuery)
              }

              VStack(spacing: 0) {
                ForEach(filteredSkills, id: \.element.skill.path) { item in
                  let skill = item.element.skill
                  let origin = item.element.origin
                  HStack(spacing: OmiSpacing.sm) {
                    Toggle(
                      "Ativar \(skill.name)",
                      isOn: Binding(
                        get: { !aiChatDisabledSkills.contains(skill.name) },
                        set: { enabled in
                          if enabled {
                            aiChatDisabledSkills.remove(skill.name)
                          } else {
                            aiChatDisabledSkills.insert(skill.name)
                          }
                          saveDisabledSkills()
                        }
                      )
                    )
                    .toggleStyle(.checkbox)
                    .labelsHidden()

                    VStack(alignment: .leading, spacing: OmiSpacing.hairline) {
                      HStack(spacing: OmiSpacing.xs) {
                        Text(skill.name)
                          .scaledFont(size: OmiType.body, weight: .medium)
                          .foregroundColor(Ink.primary)

                        // Project beats Global when both define a skill, so the two origins have
                        // to be told apart at a glance. Both branches had collapsed onto
                        // `Ink.secondary` over two washes four thousandths of an alpha apart,
                        // which is the same chip drawn twice. The chip composes its ground from
                        // its own tint, the way `SettingsStatusChip` does, so the pair cannot
                        // drift into a contrast the label does not clear.
                        let originTint = origin == "Project" ? Ink.accent : Ink.secondary
                        Text(origin == "Project" ? "Projeto" : "Global")
                          .scaledFont(size: OmiType.micro, weight: .medium)
                          .foregroundColor(originTint)
                          .padding(.horizontal, OmiSpacing.xxs)
                          .padding(.vertical, OmiSpacing.hairline)
                          .background(
                            RoundedRectangle(cornerRadius: OmiChrome.stripRadius, style: .continuous)
                              .fill(originTint.opacity(0.14))
                          )
                      }

                      if !skill.description.isEmpty {
                        Text(skill.description)
                          .scaledFont(size: OmiType.caption)
                          .foregroundColor(Ink.secondary)
                          .lineLimit(1)
                          .truncationMode(.tail)
                      }
                    }

                    Spacer()

                    Button("Ver") {
                      fileViewerTitle = "\(skill.name)/SKILL.md"
                      fileViewerContent =
                        (try? String(contentsOfFile: skill.path, encoding: .utf8))
                        ?? "Não foi possível ler o arquivo"
                      showFileViewer = true
                    }
                    .buttonStyle(OmiButtonStyle(.primary, size: .compact))
                  }
                  .padding(.vertical, OmiSpacing.xs)
                  .padding(.horizontal, OmiSpacing.xxs)

                  if item.offset != filteredSkills.last?.offset {
                    GlassSeparator()
                  }
                }
              }
            }
            .frame(maxHeight: 300)
          }
        }
      }

      // Browser Extension card
      settingsCard(settingId: "aichat.browserextension") {
        VStack(alignment: .leading, spacing: OmiSpacing.md) {
          HStack {
            Image(systemName: "globe")
              .scaledFont(size: OmiType.subheading)
              .foregroundColor(Ink.secondary)

            Text("Extensão do Navegador")
              .scaledFont(size: OmiType.subheading, weight: .semibold)
              .foregroundColor(Ink.primary)

            Spacer()

            if !playwrightExtensionToken.isEmpty {
              HStack(spacing: OmiSpacing.xxs) {
                Circle()
                  .fill(Ink.listeningGreen)
                  .frame(width: 6, height: 6)
                Text("Conectado")
                  .scaledFont(size: OmiType.caption)
                  .foregroundColor(Ink.secondary)
              }
            }

            // No `onChange` hook: `ChatProvider` and `AgentRuntimeProcess` both read this key
            // from `UserDefaults` (the former through a KVO publisher), so the `@AppStorage`
            // write *is* the propagation. An empty handler here only looked like wiring.
            Toggle("", isOn: $playwrightUseExtension)
              .toggleStyle(OmiToggleStyle())
              .controlSize(.small)
              .labelsHidden()
          }

          Text("Permite que a IA use seu navegador Chrome com todas as suas sessões logadas.")
            .scaledFont(size: OmiType.caption)
            .foregroundColor(Ink.secondary)

          if playwrightUseExtension {
            if playwrightExtensionToken.isEmpty {
              // No token — show "Set Up" button
              Button(action: {
                showBrowserSetup = true
              }) {
                HStack(spacing: OmiSpacing.xs) {
                  Image(systemName: "wrench.and.screwdriver")
                    .scaledFont(size: OmiType.caption)
                  Text("Configurar")
                    .scaledFont(size: OmiType.body, weight: .medium)
                }
              }
              .buttonStyle(OmiButtonStyle(.primary, size: .compact))
            } else {
              // Token is set — show compact view
              HStack(spacing: OmiSpacing.sm) {
                Text("Token")
                  .scaledFont(size: OmiType.caption)
                  .foregroundColor(Ink.secondary)

                Text(String(playwrightExtensionToken.prefix(8)) + "...")
                  .scaledFont(size: OmiType.caption, weight: .medium)
                  .foregroundColor(Ink.primary)
                  .font(.system(.body, design: .monospaced))

                Spacer()

                Button(action: {
                  showBrowserSetup = true
                }) {
                  HStack(spacing: OmiSpacing.xxs) {
                    Image(systemName: "arrow.clockwise")
                      .scaledFont(size: OmiType.caption)
                    Text("Reconfigurar")
                      .scaledFont(size: OmiType.caption)
                  }
                }
                .buttonStyle(OmiButtonStyle(.primary, size: .compact))

                Button(action: {
                  playwrightExtensionToken = ""
                  UserDefaults.standard.set("", forKey: "playwrightExtensionToken")
                }) {
                  HStack(spacing: OmiSpacing.xxs) {
                    Image(systemName: "arrow.counterclockwise")
                      .scaledFont(size: OmiType.caption)
                    Text("Redefinir")
                      .scaledFont(size: OmiType.caption)
                  }
                }
                .buttonStyle(OmiButtonStyle(.secondary, size: .compact))
              }
            }
          }
        }
      }

      // Dev Mode card
      settingsCard(settingId: "aichat.devmode") {
        VStack(alignment: .leading, spacing: OmiSpacing.md) {
          HStack {
            Image(systemName: "hammer")
              .scaledFont(size: OmiType.subheading)
              .foregroundColor(Ink.secondary)

            Text("Modo Desenvolvedor")
              .scaledFont(size: OmiType.subheading, weight: .semibold)
              .foregroundColor(Ink.primary)

            Spacer()

            Toggle("", isOn: $devModeEnabled)
              .toggleStyle(OmiToggleStyle())
              .controlSize(.small)
              .labelsHidden()
              .onChange(of: devModeEnabled) { _, newValue in
                AnalyticsManager.shared.settingToggled(setting: "dev_mode", enabled: newValue)
              }
          }

          Text("Permite que a IA modifique o código-fonte do app, o recompile e adicione recursos personalizados.")
            .scaledFont(size: OmiType.caption)
            .foregroundColor(Ink.secondary)

          if devModeEnabled {
            VStack(alignment: .leading, spacing: OmiSpacing.sm) {
              HStack(spacing: OmiSpacing.xs) {
                Image(systemName: "checkmark.circle.fill")
                  .foregroundColor(Ink.listeningGreen)
                  .scaledFont(size: OmiType.caption)
                Text("A IA pode modificar a interface, adicionar recursos e criar tabelas SQLite personalizadas")
                  .scaledFont(size: OmiType.caption)
                  .foregroundColor(Ink.secondary)
              }
              HStack(spacing: OmiSpacing.xs) {
                Image(systemName: "lock.fill")
                  .foregroundColor(SettingsInk.notice)
                  .scaledFont(size: OmiType.caption)
                Text("A API do backend, a autenticação e a lógica de sincronização são somente leitura")
                  .scaledFont(size: OmiType.caption)
                  .foregroundColor(Ink.secondary)
              }
            }
          }
        }
      }
    }
    .onAppear {
      refreshAIChatConfig()
      playwrightExtensionToken =
        UserDefaults.standard.string(forKey: "playwrightExtensionToken") ?? ""
    }
    // The browser-setup sheet is presented once, by `SettingsContentView.body`, because the
    // identical Browser Extension card in Advanced shares `showBrowserSetup`. A second `.sheet`
    // on the same binding inside this subtree is a competing presenter for one piece of state:
    // AppKit honours one of them and logs the other, which is a coin toss over whether "Set Up"
    // opens anything.
    .sheet(isPresented: $showFileViewer) {
      fileViewerSheet
    }
  }

  var fileViewerSheet: some View {
    VStack(spacing: 0) {
      // Header
      HStack {
        Text(fileViewerTitle)
          .scaledFont(size: OmiType.subheading, weight: .semibold)
          .foregroundColor(Ink.primary)

        Spacer()

        DismissButton(action: { showFileViewer = false })
      }
      .padding(OmiSpacing.lg)

      GlassSeparator()

      // Content
      ScrollView {
        Text(fileViewerContent)
          .font(.system(size: 12, design: .monospaced))
          .foregroundColor(Ink.secondary)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(OmiSpacing.lg)
      }
    }
    .frame(width: 600, height: 500)
    .background(Ink.wash)
  }

  /// Re-scan CLAUDE.md and skills from disk, then republish them into the cards.
  ///
  /// `refreshAIChatConfig()` copies `ChatProvider`'s already-discovered snapshot, so on its own it
  /// cannot see a skill added to `~/.claude/skills` since launch, nor a workspace chosen a moment
  /// ago. Refresh and the workspace picker both *looked* like a rescan and were a re-read of the
  /// same stale answer.
  func rediscoverAIChatConfig() async {
    if let provider = chatProvider {
      await provider.discoverClaudeConfig()
    }
    refreshAIChatConfig()
  }

  func refreshAIChatConfig() {
    // Pull skill and CLAUDE.md data directly from ChatProvider (already discovered at startup).
    // Fall back to reading from disk only when ChatProvider is unavailable.
    if let provider = chatProvider {
      aiChatClaudeMdContent = provider.claudeMdContent
      aiChatClaudeMdPath = provider.claudeMdPath
      aiChatDiscoveredSkills = provider.discoveredSkills
      aiChatProjectClaudeMdContent = provider.projectClaudeMdContent
      aiChatProjectClaudeMdPath = provider.projectClaudeMdPath
      aiChatProjectDiscoveredSkills = provider.projectDiscoveredSkills
      loadDisabledSkills()
      return
    }

    // Fallback: read from disk (used when Settings is shown before ChatProvider initializes)
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let claudeDir = "\(home)/.claude"

    let mdPath = "\(claudeDir)/CLAUDE.md"
    if FileManager.default.fileExists(atPath: mdPath),
      let content = try? String(contentsOfFile: mdPath, encoding: .utf8)
    {
      aiChatClaudeMdContent = content
      aiChatClaudeMdPath = mdPath
    } else {
      aiChatClaudeMdContent = nil
      aiChatClaudeMdPath = nil
    }

    var skills: [(name: String, description: String, path: String)] = []
    let skillsDir = "\(claudeDir)/skills"
    if let skillDirs = try? FileManager.default.contentsOfDirectory(atPath: skillsDir) {
      for dir in skillDirs.sorted() {
        let skillPath = "\(skillsDir)/\(dir)/SKILL.md"
        if FileManager.default.fileExists(atPath: skillPath),
          let content = try? String(contentsOfFile: skillPath, encoding: .utf8)
        {
          let desc = ChatProvider.extractSkillDescription(from: content)
          skills.append((name: dir, description: desc, path: skillPath))
        }
      }
    }
    aiChatDiscoveredSkills = skills

    let workspace = aiChatWorkingDirectory
    if !workspace.isEmpty, FileManager.default.fileExists(atPath: workspace) {
      let projectMdPath = "\(workspace)/CLAUDE.md"
      if FileManager.default.fileExists(atPath: projectMdPath),
        let content = try? String(contentsOfFile: projectMdPath, encoding: .utf8)
      {
        aiChatProjectClaudeMdContent = content
        aiChatProjectClaudeMdPath = projectMdPath
      } else {
        aiChatProjectClaudeMdContent = nil
        aiChatProjectClaudeMdPath = nil
      }

      var projectSkills: [(name: String, description: String, path: String)] = []
      let projectSkillsDir = "\(workspace)/.claude/skills"
      if let skillDirs = try? FileManager.default.contentsOfDirectory(atPath: projectSkillsDir) {
        for dir in skillDirs.sorted() {
          let skillPath = "\(projectSkillsDir)/\(dir)/SKILL.md"
          if FileManager.default.fileExists(atPath: skillPath),
            let content = try? String(contentsOfFile: skillPath, encoding: .utf8)
          {
            let desc = ChatProvider.extractSkillDescription(from: content)
            projectSkills.append((name: dir, description: desc, path: skillPath))
          }
        }
      }
      aiChatProjectDiscoveredSkills = projectSkills
    } else {
      aiChatProjectClaudeMdContent = nil
      aiChatProjectClaudeMdPath = nil
      aiChatProjectDiscoveredSkills = []
    }

    loadDisabledSkills()
  }

  func loadDisabledSkills() {
    let json = UserDefaults.standard.string(forKey: "disabledSkillsJSON") ?? ""
    guard let data = json.data(using: .utf8),
      let names = try? JSONDecoder().decode([String].self, from: data)
    else {
      aiChatDisabledSkills = []  // Default: nothing disabled = all enabled
      return
    }
    aiChatDisabledSkills = Set(names)
  }

  func saveDisabledSkills() {
    if let data = try? JSONEncoder().encode(Array(aiChatDisabledSkills)),
      let json = String(data: data, encoding: .utf8)
    {
      UserDefaults.standard.set(json, forKey: "disabledSkillsJSON")
    }
  }

  // MARK: - About Section

  // MARK: - Advanced Section

  struct UserStats {
    let conversations: Int
    let appsInstalled: Int
    let screenshotsTotal: Int
    let focusSessions: Int
    let tasksTodo: Int
    let tasksDone: Int
    let tasksDeleted: Int
    let goalsCount: Int
    let memoriesTotal: Int
  }

}
