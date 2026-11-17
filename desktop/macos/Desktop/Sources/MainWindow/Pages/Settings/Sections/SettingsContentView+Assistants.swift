import OmiTheme
import Sparkle
import SwiftUI
import UniformTypeIdentifiers
import WebKit

extension SettingsContentView {
  var taskAssistantSubsection: some View {
    VStack(spacing: OmiSpacing.xl) {
      settingsCard(settingId: "advanced.taskassistant") {
        VStack(alignment: .leading, spacing: OmiSpacing.lg) {
          HStack {
            Image(systemName: "checklist")
              .scaledFont(size: OmiType.subheading)
              .foregroundColor(Ink.secondary)

            Text("Assistente de Tarefas")
              .scaledFont(size: OmiType.subheading, weight: .medium)
              .foregroundColor(Ink.primary)

            Spacer()

            Toggle("", isOn: $taskEnabled)
              .toggleStyle(OmiToggleStyle())
              .labelsHidden()
              .onChange(of: taskEnabled) { _, newValue in
                TaskAssistantSettings.shared.isEnabled = newValue
                SettingsSyncManager.shared.pushPartialUpdate(
                  AssistantSettingsResponse(task: TaskSettingsResponse(enabled: newValue)))
              }
          }

          Text("Extrai tarefas e itens de ação da sua tela")
            .scaledFont(size: OmiType.body)
            .foregroundColor(Ink.secondary)

          if taskEnabled {
            GlassSeparator()

            // Extraction Interval Slider
            VStack(alignment: .leading, spacing: OmiSpacing.sm) {
              HStack {
                VStack(alignment: .leading, spacing: OmiSpacing.hairline) {
                  Text("Intervalo de Extração")
                    .scaledFont(size: OmiType.body)
                    .foregroundColor(Ink.secondary)
                  Text("Com que frequência procurar novas tarefas")
                    .scaledFont(size: OmiType.caption)
                    .foregroundColor(Ink.secondary)
                }

                Spacer()

                Text(formatExtractionInterval(taskExtractionInterval))
                  .scaledFont(size: OmiType.body, weight: .medium)
                  .foregroundColor(Ink.secondary)
                  .frame(width: 80, alignment: .trailing)
              }

              Slider(
                value: Binding(
                  get: { Double(taskIntervalSliderIndex) },
                  set: {
                    if let step = SettingsControlMetrics.ladderValue(
                      at: Int($0), in: extractionIntervalOptions)
                    {
                      taskExtractionInterval = step
                    }
                  }
                ), in: 0...Double(extractionIntervalOptions.count - 1), step: 1
              )
              .tint(SettingsSelection.valueFill)
              .onChange(of: taskExtractionInterval) { _, newValue in
                performStepHaptic()
                TaskAssistantSettings.shared.extractionInterval = newValue
                SettingsSyncManager.shared.pushPartialUpdate(
                  AssistantSettingsResponse(
                    task: TaskSettingsResponse(extractionInterval: newValue)))
              }

              offLadderStepNote(for: taskExtractionInterval, in: extractionIntervalOptions)
            }

            // Minimum Confidence Slider
            VStack(alignment: .leading, spacing: OmiSpacing.sm) {
              HStack {
                VStack(alignment: .leading, spacing: OmiSpacing.hairline) {
                  Text("Confiança Mínima")
                    .scaledFont(size: OmiType.body)
                    .foregroundColor(Ink.secondary)
                  Text("Só mostra tarefas acima deste nível de confiança")
                    .scaledFont(size: OmiType.caption)
                    .foregroundColor(Ink.secondary)
                }

                Spacer()

                Text("\(Int(taskMinConfidence * 100))%")
                  .scaledFont(size: OmiType.body, weight: .medium)
                  .foregroundColor(Ink.secondary)
                  .frame(width: 40, alignment: .trailing)
              }

              Slider(value: $taskMinConfidence, in: 0.3...0.9, step: 0.1)
                .tint(SettingsSelection.valueFill)
                .onChange(of: taskMinConfidence) { _, newValue in
                  performStepHaptic()
                  TaskAssistantSettings.shared.minConfidence = newValue
                  SettingsSyncManager.shared.pushPartialUpdate(
                    AssistantSettingsResponse(task: TaskSettingsResponse(minConfidence: newValue)))
                }
            }

            settingRow(
              title: "Prompt de Extração de Tarefas",
              subtitle: "Personalize as instruções da IA para extrair tarefas",
              settingId: "advanced.taskassistant.prompt"
            ) {
              HStack(spacing: OmiSpacing.sm) {
                Button(action: {
                  TaskTestRunnerWindow.show()
                }) {
                  HStack(spacing: OmiSpacing.xxs) {
                    Image(systemName: "play.circle")
                      .scaledFont(size: OmiType.caption)
                    Text("Executar Teste")
                      .scaledFont(size: OmiType.caption)
                  }
                }
                .buttonStyle(OmiButtonStyle(.primary, size: .compact))

                Button(action: {
                  TaskPromptEditorWindow.show()
                }) {
                  HStack(spacing: OmiSpacing.xxs) {
                    Text("Editar")
                      .scaledFont(size: OmiType.caption)
                    Image(systemName: "arrow.up.right.square")
                      .scaledFont(size: OmiType.caption)
                  }
                }
                .buttonStyle(OmiButtonStyle(.primary, size: .compact))
              }
            }

            GlassSeparator()

            // Allowed Apps for Task Extraction (Whitelist)
            VStack(alignment: .leading, spacing: OmiSpacing.md) {
              VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
                Text("Apps Permitidos")
                  .scaledFont(size: OmiType.body)
                  .foregroundColor(Ink.secondary)
                Text(
                  "As tarefas só serão extraídas destes apps. Os navegadores também são filtrados pelas palavras-chave abaixo."
                )
                .scaledFont(size: OmiType.caption)
                .foregroundColor(Ink.secondary)
              }

              // Editable list of all allowed apps
              LazyVStack(spacing: OmiSpacing.xxs) {
                ForEach(Array(taskAllowedApps).sorted(), id: \.self) { appName in
                  HStack(spacing: OmiSpacing.md) {
                    AppIconView(appName: appName, size: 20)

                    Text(appName)
                      .scaledFont(size: OmiType.body)
                      .foregroundColor(Ink.primary)

                    if TaskAssistantSettings.isBrowser(appName) {
                      Text("navegador")
                        .scaledFont(size: OmiType.micro)
                        .foregroundColor(Ink.secondary)
                        .padding(.horizontal, OmiSpacing.xs)
                        .padding(.vertical, OmiSpacing.hairline)
                        .background(Ink.rowFill)
                        .cornerRadius(OmiChrome.stripRadius)
                    }

                    Spacer()

                    Button {
                      TaskAssistantSettings.shared.disallowApp(appName)
                      taskAllowedApps = TaskAssistantSettings.shared.allowedApps
                    } label: {
                      Image(systemName: "xmark.circle.fill")
                        .scaledFont(size: OmiType.body)
                        .foregroundColor(Ink.secondary)
                    }
                    .buttonStyle(.plain)
                  }
                  .padding(.horizontal, OmiSpacing.md)
                  .padding(.vertical, OmiSpacing.xxs)
                }
              }

              AppRuleEditorView(
                title: "Adicionar App à Lista de Permitidos",
                placeholder: "Nome do app (ex.: Mail)",
                addButtonTitle: "Adicionar",
                existingApps: taskAllowedApps,
                builtInApps: TaskAssistantSettings.defaultAllowedApps,
                onAdd: { appName in
                  TaskAssistantSettings.shared.allowApp(appName)
                  taskAllowedApps = TaskAssistantSettings.shared.allowedApps
                }
              )
            }

            GlassSeparator()

            // Browser Window Keywords
            VStack(alignment: .leading, spacing: OmiSpacing.md) {
              VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
                Text("Palavras-chave de Janelas do Navegador")
                  .scaledFont(size: OmiType.body)
                  .foregroundColor(Ink.secondary)
                Text(
                  "Em apps de navegador, só analisa janelas cujo título contenha uma destas palavras-chave."
                )
                .scaledFont(size: OmiType.caption)
                .foregroundColor(Ink.secondary)
              }

              // Keyword chips (filterable, deletable)
              BrowserKeywordListView(
                keywords: $taskBrowserKeywords,
                onAdd: { keyword in
                  TaskAssistantSettings.shared.addBrowserKeyword(keyword)
                  taskBrowserKeywords = TaskAssistantSettings.shared.browserKeywords
                },
                onRemove: { keyword in
                  TaskAssistantSettings.shared.removeBrowserKeyword(keyword)
                  taskBrowserKeywords = TaskAssistantSettings.shared.browserKeywords
                }
              )
            }

            GlassSeparator()

            // Task Prioritization Re-score
            settingRow(
              title: "Priorização de Tarefas",
              subtitle: "Reavalia todas as tarefas pela relevância para seu perfil e suas metas",
              settingId: "advanced.taskassistant.prioritization"
            ) {
              if isRescoringTasks {
                ProgressView()
                  .controlSize(.small)
              } else {
                Button(action: {
                  isRescoringTasks = true
                  Task {
                    await TaskPrioritizationService.shared.forceFullRescore()
                    await MainActor.run { isRescoringTasks = false }
                  }
                }) {
                  HStack(spacing: OmiSpacing.xxs) {
                    Image(systemName: "arrow.trianglehead.counterclockwise")
                      .scaledFont(size: OmiType.caption)
                    Text("Reavaliar")
                      .scaledFont(size: OmiType.caption)
                  }
                }
                .buttonStyle(OmiButtonStyle(.primary, size: .compact))
              }
            }
          }  // end if taskEnabled
        }
      }
    }
  }

  var memoryAssistantSubsection: some View {
    VStack(spacing: OmiSpacing.xl) {
      settingsCard(settingId: "advanced.memoryassistant") {
        VStack(alignment: .leading, spacing: OmiSpacing.lg) {
          HStack {
            Image(systemName: "brain.head.profile")
              .scaledFont(size: OmiType.subheading)
              .foregroundColor(Ink.secondary)

            Text("Assistente de Memórias")
              .scaledFont(size: OmiType.subheading, weight: .medium)
              .foregroundColor(Ink.primary)

            Spacer()

            Toggle("", isOn: $memoryEnabled)
              .toggleStyle(OmiToggleStyle())
              .labelsHidden()
              .onChange(of: memoryEnabled) { _, newValue in
                MemoryAssistantSettings.shared.applyUserSettingChange(.enabled, value: newValue)
                SettingsSyncManager.shared.pushPartialUpdate(
                  AssistantSettingsResponse(memory: MemorySettingsResponse(enabled: newValue)))
              }
          }

          Text("Extrai fatos e aprendizados da sua tela")
            .scaledFont(size: OmiType.body)
            .foregroundColor(Ink.secondary)

          if memoryEnabled {
            GlassSeparator()

            // Extraction Interval Slider
            VStack(alignment: .leading, spacing: OmiSpacing.sm) {
              HStack {
                VStack(alignment: .leading, spacing: OmiSpacing.hairline) {
                  Text("Intervalo de Extração")
                    .scaledFont(size: OmiType.body)
                    .foregroundColor(Ink.secondary)
                  Text("Com que frequência procurar novas memórias")
                    .scaledFont(size: OmiType.caption)
                    .foregroundColor(Ink.secondary)
                }

                Spacer()

                Text(formatExtractionInterval(memoryExtractionInterval))
                  .scaledFont(size: OmiType.body, weight: .medium)
                  .foregroundColor(Ink.secondary)
                  .frame(width: 80, alignment: .trailing)
              }

              Slider(
                value: Binding(
                  get: { Double(memoryIntervalSliderIndex) },
                  set: {
                    if let step = SettingsControlMetrics.ladderValue(
                      at: Int($0), in: extractionIntervalOptions)
                    {
                      memoryExtractionInterval = step
                    }
                  }
                ), in: 0...Double(extractionIntervalOptions.count - 1), step: 1
              )
              .tint(SettingsSelection.valueFill)
              .onChange(of: memoryExtractionInterval) { _, newValue in
                performStepHaptic()
                MemoryAssistantSettings.shared.extractionInterval = newValue
                SettingsSyncManager.shared.pushPartialUpdate(
                  AssistantSettingsResponse(
                    memory: MemorySettingsResponse(extractionInterval: newValue)))
              }

              offLadderStepNote(for: memoryExtractionInterval, in: extractionIntervalOptions)
            }

            // Minimum Confidence Slider
            VStack(alignment: .leading, spacing: OmiSpacing.sm) {
              HStack {
                VStack(alignment: .leading, spacing: OmiSpacing.hairline) {
                  Text("Confiança Mínima")
                    .scaledFont(size: OmiType.body)
                    .foregroundColor(Ink.secondary)
                  Text("Só salva memórias acima deste nível de confiança")
                    .scaledFont(size: OmiType.caption)
                    .foregroundColor(Ink.secondary)
                }

                Spacer()

                Text("\(Int(memoryMinConfidence * 100))%")
                  .scaledFont(size: OmiType.body, weight: .medium)
                  .foregroundColor(Ink.secondary)
                  .frame(width: 40, alignment: .trailing)
              }

              Slider(value: $memoryMinConfidence, in: 0.5...0.95, step: 0.05)
                .tint(SettingsSelection.valueFill)
                .onChange(of: memoryMinConfidence) { _, newValue in
                  performStepHaptic()
                  MemoryAssistantSettings.shared.minConfidence = newValue
                  SettingsSyncManager.shared.pushPartialUpdate(
                    AssistantSettingsResponse(
                      memory: MemorySettingsResponse(minConfidence: newValue)))
                }
            }

            settingRow(
              title: "Prompt de Extração de Memórias",
              subtitle: "Personalize as instruções da IA para extrair memórias",
              settingId: "advanced.memoryassistant.prompt"
            ) {
              Button(action: {
                MemoryPromptEditorWindow.show()
              }) {
                HStack(spacing: OmiSpacing.xxs) {
                  Text("Editar")
                    .scaledFont(size: OmiType.caption)
                  Image(systemName: "arrow.up.right.square")
                    .scaledFont(size: OmiType.caption)
                }
              }
              .buttonStyle(OmiButtonStyle(.primary, size: .compact))
            }

            GlassSeparator()

            // Excluded Apps for Memory Extraction
            VStack(alignment: .leading, spacing: OmiSpacing.md) {
              VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
                Text("Apps Excluídos")
                  .scaledFont(size: OmiType.body)
                  .foregroundColor(Ink.secondary)
                Text("Não serão extraídas memórias destes apps")
                  .scaledFont(size: OmiType.caption)
                  .foregroundColor(Ink.secondary)
              }

              // Built-in system exclusions (non-removable, shared across assistants)
              DisclosureGroup {
                LazyVStack(spacing: OmiSpacing.xxs) {
                  ForEach(Array(TaskAssistantSettings.builtInExcludedApps).sorted(), id: \.self) {
                    appName in
                    HStack(spacing: OmiSpacing.md) {
                      AppIconView(appName: appName, size: 20)

                      Text(appName)
                        .scaledFont(size: OmiType.body)
                        .foregroundColor(Ink.secondary)

                      Spacer()
                    }
                    .padding(.horizontal, OmiSpacing.md)
                    .padding(.vertical, OmiSpacing.xxs)
                  }
                }
              } label: {
                Text(
                  "Apps do sistema sempre excluídos (\(TaskAssistantSettings.builtInExcludedApps.count))"
                )
                .scaledFont(size: OmiType.caption)
                .foregroundColor(Ink.secondary)
              }
              .tint(Ink.secondary)

              if !memoryExcludedApps.isEmpty {
                LazyVStack(spacing: OmiSpacing.sm) {
                  ForEach(Array(memoryExcludedApps).sorted(), id: \.self) { appName in
                    ExcludedAppRow(
                      appName: appName,
                      onRemove: {
                        MemoryAssistantSettings.shared.includeApp(appName)
                        memoryExcludedApps = MemoryAssistantSettings.shared.excludedApps
                      }
                    )
                  }
                }
              }

              AppRuleEditorView(
                title: "Adicionar App à Lista de Exclusão",
                placeholder: "Nome do app (ex.: Senhas)",
                addButtonTitle: "Adicionar",
                existingApps: memoryExcludedApps,
                builtInApps: TaskAssistantSettings.builtInExcludedApps,
                onAdd: { appName in
                  MemoryAssistantSettings.shared.excludeApp(appName)
                  memoryExcludedApps = MemoryAssistantSettings.shared.excludedApps
                }
              )
            }
          }  // end if memoryEnabled
        }
      }
    }
  }

  var analysisThrottleSubsection: some View {
    VStack(spacing: OmiSpacing.xl) {
      settingsCard(settingId: "advanced.analysisthrottle") {
        VStack(alignment: .leading, spacing: OmiSpacing.sm) {
          HStack {
            VStack(alignment: .leading, spacing: OmiSpacing.hairline) {
              Text("Limite de Análise")
                .scaledFont(size: OmiType.body)
                .foregroundColor(Ink.secondary)
              Text("Espera antes de analisar depois de trocar de app")
                .scaledFont(size: OmiType.caption)
                .foregroundColor(Ink.secondary)
            }

            Spacer()

            Text(formatAnalysisDelay(analysisDelay))
              .scaledFont(size: OmiType.body, weight: .medium)
              .foregroundColor(Ink.secondary)
              .frame(width: 80, alignment: .trailing)
          }

          Slider(
            value: Binding(
              get: { Double(analysisDelaySliderIndex) },
              set: {
                if let step = SettingsControlMetrics.ladderValue(
                  at: Int($0), in: analysisDelayOptions)
                {
                  analysisDelay = step
                }
              }
            ), in: 0...Double(analysisDelayOptions.count - 1), step: 1
          )
          .tint(SettingsSelection.valueFill)
          .onChange(of: analysisDelay) { _, newValue in
            performStepHaptic()
            AssistantSettings.shared.analysisDelay = newValue
            SettingsSyncManager.shared.pushPartialUpdate(
              AssistantSettingsResponse(
                shared: SharedAssistantSettingsResponse(analysisDelay: newValue)))
          }

          offLadderStepNote(for: analysisDelay, in: analysisDelayOptions)
        }
      }
    }
  }

  var goalsSubsection: some View {
    VStack(spacing: OmiSpacing.xl) {
      settingsCard(settingId: "advanced.goals") {
        VStack(alignment: .leading, spacing: OmiSpacing.lg) {
          HStack {
            Image(systemName: "target")
              .scaledFont(size: OmiType.subheading)
              .foregroundColor(Ink.secondary)

            Text("Metas")
              .scaledFont(size: OmiType.subheading, weight: .medium)
              .foregroundColor(Ink.primary)

            Spacer()
          }

          Text("Acompanhe metas pessoais com detecção de progresso por IA a partir das suas conversas")
            .scaledFont(size: OmiType.body)
            .foregroundColor(Ink.secondary)

          GlassSeparator()

          settingRow(
            title: "Gerar Metas Automaticamente",
            subtitle: "Sugere novas metas todo dia com base nas suas conversas e tarefas",
            settingId: "advanced.goals.autogenerate"
          ) {
            Toggle("", isOn: $goalsAutoGenerateEnabled)
              .toggleStyle(OmiToggleStyle())
              .labelsHidden()
              .onChange(of: goalsAutoGenerateEnabled) { _, newValue in
                GoalGenerationService.shared.isAutoGenerationEnabled = newValue
              }
          }
        }
      }
    }
  }

  var preferencesSubsection: some View {
    VStack(spacing: OmiSpacing.xl) {
      settingsCard(settingId: "advanced.preferences.speaknotifications") {
        HStack(spacing: OmiSpacing.lg) {
          Image(systemName: "speaker.wave.2")
            .scaledFont(size: OmiType.subheading)
            .foregroundColor(Ink.secondary)
            .frame(width: 24, height: 24)

          VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
            Text("Falar Notificações em Voz Alta")
              .scaledFont(size: OmiType.subheading, weight: .semibold)
              .foregroundColor(Ink.primary)

            Text("Lê em voz alta as notificações proativas quando chegam, usando a voz do seu chat")
              .scaledFont(size: OmiType.body)
              .foregroundColor(Ink.secondary)
          }

          Spacer()

          Toggle("", isOn: $speakNotificationsAloud)
            .toggleStyle(OmiToggleStyle())
            .labelsHidden()
        }
      }

      // Launch at Login toggle
      settingsCard(settingId: "advanced.preferences.launchatlogin") {
        HStack(spacing: OmiSpacing.lg) {
          Image(systemName: "power")
            .scaledFont(size: OmiType.subheading)
            .foregroundColor(Ink.secondary)
            .frame(width: 24, height: 24)

          VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
            Text("Abrir ao Iniciar a Sessão")
              .scaledFont(size: OmiType.subheading, weight: .semibold)
              .foregroundColor(Ink.primary)

            Text(launchAtLoginManager.statusDescription)
              .scaledFont(size: OmiType.body)
              .foregroundColor(Ink.secondary)
          }

          Spacer()

          Toggle(
            "",
            isOn: Binding(
              get: { launchAtLoginManager.isEnabled },
              set: { newValue in
                // Record the user's explicit choice before touching the system
                // so a failed unregister still counts as "declined" and the
                // default-on migration never overrides it.
                LaunchAtLoginPreference.recordUserChoice(enabled: newValue)
                if launchAtLoginManager.setEnabled(newValue) {
                  AnalyticsManager.shared.launchAtLoginChanged(enabled: newValue, source: "user")
                }
              }
            )
          )
          .toggleStyle(OmiToggleStyle())
          .labelsHidden()
        }
      }
    }
  }

  var troubleshootingSubsection: some View {
    VStack(spacing: OmiSpacing.xl) {
      // Report Issue
      settingsCard(settingId: "advanced.troubleshooting.reportissue") {
        HStack(spacing: OmiSpacing.lg) {
          Image(systemName: "exclamationmark.bubble")
            .scaledFont(size: OmiType.subheading)
            .foregroundColor(Ink.secondary)
            .frame(width: 24, height: 24)

          VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
            Text("Reportar Problema")
              .scaledFont(size: OmiType.subheading, weight: .semibold)
              .foregroundColor(Ink.primary)

            Text("Salva neste Mac um relatório com dados ocultados para compartilhar manualmente")
              .scaledFont(size: OmiType.body)
              .foregroundColor(Ink.secondary)
          }

          Spacer()

          Button(action: {
            FeedbackWindow.show(userEmail: AuthState.shared.userEmail)
          }) {
            Text("Reportar")
          }
          .buttonStyle(OmiButtonStyle(.primary, size: .compact))
        }
      }

      // Rescan Files
      settingsCard(settingId: "advanced.troubleshooting.rescanfiles") {
        RescanFilesRow(showConfirmation: $showRescanFilesAlert)
      }

      // Reset Integration Suggestions
      settingsCard(settingId: "advanced.troubleshooting.resetintegrationsuggestions") {
        HStack(spacing: OmiSpacing.lg) {
          Image(systemName: "sparkles.rectangle.stack")
            .scaledFont(size: OmiType.subheading)
            .foregroundColor(Ink.secondary)
            .frame(width: 24, height: 24)

          VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
            Text("Redefinir Sugestões de Integrações")
              .scaledFont(size: OmiType.subheading, weight: .semibold)
              .foregroundColor(Ink.primary)

            Text("Limpa o histórico de sugestões de todas as integrações, inclusive as que você ocultou, para o Omi poder oferecê-las de novo")
              .scaledFont(size: OmiType.body)
              .foregroundColor(Ink.secondary)
          }

          Spacer()

          Button("Redefinir…") {
            isConfirmingNudgeReset = true
          }
          .buttonStyle(OmiButtonStyle(.secondary, size: .compact))
        }
      }
      .shellConfirmation(
        isPresented: $isConfirmingNudgeReset,
        title: "Redefinir Sugestões de Integrações?",
        message: "O histórico de sugestões de todas as integrações é limpo, inclusive das que você ocultou, então o Omi pode "
          + "sugeri-las de novo. Isso não pode ser desfeito.",
        confirmTitle: "Redefinir"
      ) {
        IntegrationNudgeStore.shared.resetAll()
      }
    }
  }

  // MARK: - Reset Onboarding Subsection

  var resetOnboardingSubsection: some View {
    VStack(spacing: OmiSpacing.xl) {
      settingsCard(settingId: "advanced.resetonboarding") {
        HStack(spacing: OmiSpacing.lg) {
          Image(systemName: "arrow.counterclockwise")
            .scaledFont(size: OmiType.subheading)
            .foregroundColor(Ink.secondary)
            .frame(width: 24, height: 24)

          VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
            Text("Refazer Introdução")
              .scaledFont(size: OmiType.subheading, weight: .semibold)
              .foregroundColor(Ink.primary)

            Text("Reinicia o assistente de configuração só para esta versão do app")
              .scaledFont(size: OmiType.body)
              .foregroundColor(Ink.secondary)
          }

          Spacer()

          // Raises the confirmation; `SettingsPage` presents it. `.alert` dims the *window*, and this
          // window is a transparent rectangle larger than the panels in it, so the system's backdrop
          // landed on the wallpaper — see `ShellConfirmationDialog`.
          Button(action: { showResetOnboardingConfirm = true }) {
            Text("Redefinir")
          }
          .buttonStyle(OmiButtonStyle(.primary, size: .compact))
        }
      }
    }
  }

  // MARK: - Gmail Reader Subsection

  /// Re-reads every assistant control from the store that owns it.
  ///
  /// These cards are seeded from their singletons once, in `SettingsContentView.init`. Opening
  /// Settings then runs `loadBackendSettings()`, which awaits `SettingsSyncManager.syncFromServer()`
  /// — server-authoritative by design, and it rewrites exactly those singletons underneath the pane.
  /// Nothing told the pane, so the switches, sliders and app lists kept painting the pre-sync values
  /// until the next relaunch: a per-device answer to a per-account question. The sync manager already
  /// announces itself with `.assistantSettingsDidSyncFromServer`; `advancedSection` subscribes, and
  /// this is what it runs. Same shape as
  /// `syncNotificationTogglesFromAssistantSettings()` in `SettingsContentView+NotificationsPrivacy`.
  ///
  /// A sync that agrees with the pane assigns nothing, so the common case does not re-enter the
  /// `onChange` handlers above. A sync that corrects the pane does, and each handler then writes the
  /// value the server just supplied back to the same singleton — a no-op write whose partial update
  /// restates the server's own value, and whose telemetry sees no change to report.
  func syncAssistantControlsFromSettings() {
    let values = AssistantControlValues.current()
    taskEnabled = values.taskEnabled
    taskExtractionInterval = values.taskExtractionInterval
    taskMinConfidence = values.taskMinConfidence
    taskAllowedApps = values.taskAllowedApps
    taskBrowserKeywords = values.taskBrowserKeywords
    memoryEnabled = values.memoryEnabled
    memoryExtractionInterval = values.memoryExtractionInterval
    memoryMinConfidence = values.memoryMinConfidence
    memoryExcludedApps = values.memoryExcludedApps
    analysisDelay = values.analysisDelay
  }

}

// MARK: - Assistant Control Projection

/// Everything the three assistant cards and the analysis throttle paint, read from the stores that
/// own them.
///
/// Naming the projection separately is what lets the account-sync path be asserted without standing
/// up a SwiftUI host: a test can apply a server snapshot through `SettingsSyncManager` and compare
/// this against it. It is deliberately only the settings `SettingsSyncManager.applyRemoteSettings`
/// can rewrite — the task agent's chat toggle and working directory are local to this Mac and are
/// not the account's to correct.
struct AssistantControlValues: Equatable {
  var taskEnabled: Bool
  var taskExtractionInterval: TimeInterval
  var taskMinConfidence: Double
  var taskAllowedApps: Set<String>
  var taskBrowserKeywords: [String]
  var memoryEnabled: Bool
  var memoryExtractionInterval: TimeInterval
  var memoryMinConfidence: Double
  var memoryExcludedApps: Set<String>
  var analysisDelay: Int

  @MainActor
  static func current() -> AssistantControlValues {
    AssistantControlValues(
      taskEnabled: TaskAssistantSettings.shared.isEnabled,
      taskExtractionInterval: TaskAssistantSettings.shared.extractionInterval,
      taskMinConfidence: TaskAssistantSettings.shared.minConfidence,
      taskAllowedApps: TaskAssistantSettings.shared.allowedApps,
      taskBrowserKeywords: TaskAssistantSettings.shared.browserKeywords,
      memoryEnabled: MemoryAssistantSettings.shared.isEnabled,
      memoryExtractionInterval: MemoryAssistantSettings.shared.extractionInterval,
      memoryMinConfidence: MemoryAssistantSettings.shared.minConfidence,
      memoryExcludedApps: MemoryAssistantSettings.shared.excludedApps,
      analysisDelay: AssistantSettings.shared.analysisDelay
    )
  }
}

// MARK: - Rescan Files

/// What the Rescan Files row is allowed to claim, and the sentence it shows for it.
///
/// The row used to promise it would "update your AI profile", then post a notification whose only
/// listener runs `FileIndexerService.backgroundRescan()` — an incremental re-index of file
/// *metadata* that never touches the profile. (Regenerating the profile is the Advanced page's own
/// separate button.) It also gave no sign it had done anything: press Rescan, and every pixel on
/// the row stayed exactly as it was, whether the scan ran, finished, or never started. Claim and
/// evidence live here together so neither can drift without the other.
enum FileRescanState: Equatable {
  case idle
  case scanning
  case finished(indexedFiles: Int)

  var subtitle: String {
    switch self {
    case .idle:
      return "Reindexa os arquivos das suas pastas padrão"
    case .scanning:
      return "Reindexando arquivos…"
    case .finished(let indexedFiles):
      // A zero is not evidence of an empty Mac: `getIndexedFileCount()` also answers 0 when the
      // local database could not be opened, so the count is only stated when there is one.
      guard indexedFiles > 0 else { return "Reindexação concluída" }
      return "Reindexado, \(indexedFiles) arquivo\(indexedFiles == 1 ? "" : "s") no índice"
    }
  }
}

/// Settings ▸ Advanced ▸ Troubleshooting ▸ Rescan Files.
///
/// A view of its own because the progress it now reports is per-row transient state, and
/// `SettingsContentView` is one struct shared by every settings section — its stored properties are
/// the wrong place for a flag that only this row can be in.
struct RescanFilesRow: View {
  @Binding var showConfirmation: Bool
  @State private var state: FileRescanState = .idle

  var body: some View {
    HStack(spacing: OmiSpacing.lg) {
      Image(systemName: "folder.badge.gearshape")
        .scaledFont(size: OmiType.subheading)
        .foregroundColor(Ink.secondary)
        .frame(width: 24, height: 24)

      VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
        Text("Reexaminar Arquivos")
          .scaledFont(size: OmiType.subheading, weight: .semibold)
          .foregroundColor(Ink.primary)

        Text(state.subtitle)
          .scaledFont(size: OmiType.body)
          .foregroundColor(Ink.secondary)
      }

      Spacer()

      if state == .scanning {
        ProgressView()
          .controlSize(.small)
      } else {
        Button(action: { showConfirmation = true }) {
          Text("Reexaminar")
        }
        .buttonStyle(OmiButtonStyle(.primary, size: .compact))
      }
    }
    .shellConfirmation(
      isPresented: $showConfirmation,
      title: "Reexaminar Arquivos?",
      message: "O Omi relê os nomes, tamanhos e pastas dos arquivos das suas pastas padrão para que os "
        + "recentes possam ser buscados. O conteúdo dos arquivos não é lido.",
      confirmTitle: "Reexaminar",
      isDestructive: false
    ) {
      rescan()
    }
  }

  private func rescan() {
    state = .scanning
    Task {
      await FileIndexerService.shared.backgroundRescan()
      let indexed = await FileIndexerService.shared.getIndexedFileCount()
      state = .finished(indexedFiles: indexed)
    }
  }
}
