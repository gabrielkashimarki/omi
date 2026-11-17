import OmiTheme
import Sparkle
import SwiftUI
import UniformTypeIdentifiers
import WebKit

extension SettingsContentView {
  func advancedCategoryHeader(title: String, icon: String) -> some View {
    HStack(spacing: OmiSpacing.sm) {
      Image(systemName: icon)
        .scaledFont(size: OmiType.subheading)
        .foregroundColor(Ink.secondary)
      Text(title)
        .scaledFont(size: OmiType.heading, weight: .semibold)
        .foregroundColor(Ink.primary)
      Spacer()
    }
    .padding(.top, OmiSpacing.lg)
  }

  var advancedSection: some View {
    VStack(spacing: OmiSpacing.xxl) {
      advancedCategoryHeader(title: "Configuração da IA", icon: "cpu")
      aiSetupSubsection
      advancedCategoryHeader(title: "Conectar um Agente", icon: "point.3.connected.trianglepath.dotted")
      connectAgentSubsection
      // HIDDEN DELIBERATELY (Nik, 2026-08-25): the Task/Insight/Memory Assistant panes are
      // intentionally not rendered. This is product direction, not dead code — do NOT re-wire
      // them the way 73c7f85fbc ("give the three proactive assistants a pane you can reach")
      // did after the last hide. The assistants themselves keep running with their stored
      // settings; only the settings UI is hidden.
      // advancedCategoryHeader(title: "Task Assistant", icon: "checklist")
      // taskAssistantSubsection
      // advancedCategoryHeader(title: "Insight Assistant", icon: ProactiveNotificationBadge.insightSystemImage)
      // insightAssistantSubsection
      // advancedCategoryHeader(title: "Memory Assistant", icon: "brain.head.profile")
      // memoryAssistantSubsection
      advancedCategoryHeader(title: "Limite de Análise", icon: "clock.arrow.2.circlepath")
      analysisThrottleSubsection

      DisclosureGroup(isExpanded: $advancedDetailsExpanded) {
        VStack(spacing: OmiSpacing.xxl) {
          advancedCategoryHeader(title: "Perfil e Estatísticas", icon: "brain")
          profileAndStatsSubsection
          advancedCategoryHeader(title: "Refazer Introdução", icon: "arrow.counterclockwise")
          resetOnboardingSubsection
          advancedCategoryHeader(title: "Metas", icon: "target")
          goalsSubsection
          advancedCategoryHeader(title: "Preferências", icon: "slider.horizontal.3")
          preferencesSubsection
          advancedCategoryHeader(title: "Solução de Problemas", icon: "wrench.and.screwdriver")
          troubleshootingSubsection
          if AppBuild.isBetaProductionBundle {
            advancedCategoryHeader(title: "Diagnóstico Beta", icon: "waveform.path.ecg")
            betaDiagnosticsSubsection
          }
          advancedCategoryHeader(title: "Chaves dos Provedores de Modelo", icon: "key")
          developerKeysSubsection
        }
        .padding(.top, OmiSpacing.md)
      } label: {
        HStack(spacing: OmiSpacing.sm) {
          Image(systemName: "wrench.and.screwdriver")
            .scaledFont(size: OmiType.subheading)
            .foregroundStyle(Ink.secondary)
          Text("Avançado")
            .scaledFont(size: OmiType.heading, weight: .semibold)
            .foregroundStyle(Ink.primary)
        }
      }
      .tint(Ink.secondary)
      .padding(.top, OmiSpacing.lg)
      .accessibilityIdentifier("settings-ai-automation-advanced-disclosure")
    }
    // The assistant cards above are seeded from their singletons when the pane is constructed, but
    // `loadBackendSettings()` then runs `SettingsSyncManager.syncFromServer()`, which is
    // server-authoritative and rewrites those same singletons underneath us. Without this the
    // switches, sliders and app lists kept painting the pre-sync values — a per-device answer to a
    // per-account question — until the next relaunch. The sync manager already announces itself;
    // this is the pane agreeing to listen. Same shape as the Notifications pane.
    .onReceive(NotificationCenter.default.publisher(for: .assistantSettingsDidSyncFromServer)) { _ in
      syncAssistantControlsFromSettings()
    }
    .onChange(of: highlightedSettingId) { _, settingId in
      // Search and deep links must still reveal cards tucked into the collapsed
      // secondary section. The default presentation stays compact until a
      // specific result asks for that content.
      if settingId != nil {
        advancedDetailsExpanded = true
      }
    }
  }

  // MARK: - Beta Diagnostics

  var betaDiagnosticsSubsection: some View {
    settingsCard(settingId: "advanced.beta.enhanced_diagnostics") {
      HStack(spacing: OmiSpacing.lg) {
        Image(systemName: "waveform.path.ecg")
          .scaledFont(size: OmiType.subheading)
          .foregroundColor(Ink.secondary)
          .frame(width: 24, height: 24)

        VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
          Text("Diagnóstico Avançado")
            .scaledFont(size: OmiType.subheading, weight: .semibold)
            .foregroundColor(Ink.primary)
          Text(
            "Compartilhe contexto técnico adicional das falhas para melhorar este beta. Não inclui prompts, transcrições nem arquivos de log brutos."
          )
          .scaledFont(size: OmiType.body)
          .foregroundColor(Ink.secondary)
        }

        Spacer()

        Toggle("Diagnóstico Avançado", isOn: $betaEnhancedDiagnosticsEnabled)
          .toggleStyle(OmiToggleStyle())
          .labelsHidden()
      }
    }
  }

  // MARK: - Advanced Subsections

  var aiSetupSubsection: some View {
    VStack(spacing: OmiSpacing.xl) {
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
        }
      }

      settingsCard(settingId: "aichat.meetingbriefs") {
        VStack(alignment: .leading, spacing: OmiSpacing.md) {
          HStack(spacing: OmiSpacing.md) {
            Image(systemName: "calendar.badge.clock")
              .scaledFont(size: OmiType.subheading)
              .foregroundColor(Ink.secondary)

            Text("Resumos Prévios de Reunião")
              .scaledFont(size: OmiType.subheading, weight: .semibold)
              .foregroundColor(Ink.primary)

            Spacer()

            Toggle(
              "",
              isOn: Binding(
                get: { meetingMemoryBriefsEnabled },
                set: { enabled in
                  meetingBriefAccessRequestGeneration += 1
                  let generation = meetingBriefAccessRequestGeneration
                  if !enabled {
                    meetingMemoryBriefsEnabled = false
                    meetingBriefCalendarAccessUnavailable = false
                    return
                  }
                  Task {
                    let allowed = await SystemCalendarMeetingContextService.shared.requestBriefAccess()
                    guard generation == meetingBriefAccessRequestGeneration else { return }
                    if allowed {
                      meetingMemoryBriefsEnabled = true
                      meetingBriefCalendarAccessUnavailable = false
                    } else {
                      meetingBriefCalendarAccessUnavailable = true
                      OmiToastCenter.shared.notice(
                        "Permita o acesso ao Calendário nos Ajustes do Sistema do macOS para ver os resumos prévios de reunião.",
                        systemImage: "calendar.badge.exclamationmark")
                    }
                  }
                }
              )
            )
            .toggleStyle(OmiToggleStyle())
            .labelsHidden()
            .accessibilityLabel("Resumos Prévios de Reunião")
          }

          Text(
            "Contexto discreto, com links para as fontes, até duas horas antes de uma reunião correspondente. Usa o calendário deste Mac; nada é publicado no Chat nem enviado automaticamente."
          )
          .scaledFont(size: OmiType.caption)
          .foregroundColor(Ink.secondary)

          if meetingBriefCalendarAccessUnavailable {
            Text(
              "O acesso ao Calendário está desligado. Abra Ajustes do Sistema → Privacidade e Segurança → Calendários, permita este app e ligue os Resumos Prévios de Reunião de novo."
            )
            .scaledFont(size: OmiType.caption)
            .foregroundColor(Ink.secondary)
            .accessibilityIdentifier("meeting-brief-calendar-access-help")
          }
        }
      }
    }
  }

  var profileAndStatsSubsection: some View {
    VStack(spacing: OmiSpacing.xl) {
      settingsCard(settingId: "advanced.profileandstats") {
        VStack(alignment: .leading, spacing: OmiSpacing.md) {
          HStack(spacing: OmiSpacing.md) {
            Image(systemName: showProfileAndStats ? "eye.slash" : "eye")
              .scaledFont(size: OmiType.subheading)
              .foregroundColor(Ink.secondary)

            VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
              Text("Perfil e Estatísticas")
                .scaledFont(size: OmiType.subheading, weight: .semibold)
                .foregroundColor(Ink.primary)
              Text("Mantém o perfil gerado e as estatísticas de uso ocultos até você precisar.")
                .scaledFont(size: OmiType.caption)
                .foregroundColor(Ink.secondary)
            }

            Spacer()

            Button(showProfileAndStats ? "Ocultar" : "Mostrar") {
              OmiMotion.withGated(.easeInOut(duration: 0.2)) {
                showProfileAndStats.toggle()
              }
            }
            .buttonStyle(OmiButtonStyle(.primary, size: .compact))
          }
        }
      }

      if showProfileAndStats {
        aiUserProfileSubsection
          .shellConfirmation(
            isPresented: $isConfirmingAIProfileDelete,
            title: "Apagar o Perfil de Usuário da IA?",
            message: "O Omi esquece este perfil. Um novo é gerado na próxima abertura ou com Gerar Agora.",
            confirmTitle: "Apagar"
          ) {
            deleteCurrentAIProfile()
          }
        statsSubsection
      }
    }
  }

  var aiUserProfileSubsection: some View {
    VStack(spacing: OmiSpacing.xl) {
      settingsCard(settingId: "advanced.aiuserprofile") {
        VStack(alignment: .leading, spacing: OmiSpacing.lg) {
          HStack(spacing: OmiSpacing.sm) {
            Image(systemName: "brain")
              .scaledFont(size: OmiType.subheading)
              .foregroundColor(Ink.secondary)

            Text("Perfil de Usuário da IA")
              .scaledFont(size: OmiType.subheading, weight: .medium)
              .foregroundColor(Ink.primary)

            Spacer()

            if isGeneratingAIProfile {
              ProgressView()
                .controlSize(.small)
            } else {
              Button(action: {
                regenerateAIProfile()
              }) {
                Text(aiProfileText == nil ? "Gerar Agora" : "Gerar de Novo")
                  .scaledFont(size: OmiType.caption)
              }
              .buttonStyle(OmiButtonStyle(.primary, size: .compact))
            }
          }

          GlassSeparator()

          if let text = aiProfileText {
            if isEditingAIProfile {
              TextEditor(text: $aiProfileEditText)
                .scaledFont(size: OmiType.body, design: .monospaced)
                .foregroundColor(Ink.secondary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 120, maxHeight: 300)

              HStack {
                Button("Cancelar") {
                  isEditingAIProfile = false
                }
                .buttonStyle(OmiButtonStyle(.primary, size: .compact))

                Button("Salvar") {
                  if let id = aiProfileId {
                    Task {
                      let success = await AIUserProfileService.shared.updateProfileText(
                        id: id, newText: aiProfileEditText
                      )
                      if success {
                        aiProfileText = aiProfileEditText
                        isEditingAIProfile = false
                      }
                      // A rejected save used to close the editor anyway, which
                      // threw the edit away and looked exactly like a save that
                      // worked. Leave the editor open with the text intact so
                      // the edit survives and can be retried.
                    }
                  }
                }
                .buttonStyle(OmiButtonStyle(.primary, size: .compact))

                Spacer()
              }
            } else {
              ScrollView {
                Text(text)
                  .scaledFont(size: OmiType.body, design: .monospaced)
                  .foregroundColor(Ink.secondary)
                  .textSelection(.enabled)
                  .if_available_writingToolsNone()
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
              .frame(maxHeight: 200)

              HStack {
                if let date = aiProfileGeneratedAt {
                  Text("Última atualização: \(date.formatted(.relative(presentation: .named)))")
                    .scaledFont(size: OmiType.caption)
                    .foregroundColor(Ink.secondary)
                }

                Spacer()

                if aiProfileDataSourcesUsed > 0 {
                  Text("Fontes de dados: \(aiProfileDataSourcesUsed) itens")
                    .scaledFont(size: OmiType.caption)
                    .foregroundColor(Ink.secondary)
                }

                OmiIconButton("pencil", help: "Editar Perfil", size: .compact) {
                  aiProfileEditText = text
                  isEditingAIProfile = true
                }

                OmiIconButton("trash", help: "Apagar Perfil…", size: .compact, isDestructive: true) {
                  isConfirmingAIProfileDelete = true
                }
              }
            }
          } else if !isGeneratingAIProfile {
            Text(
              "Seu perfil de usuário da IA será gerado automaticamente na próxima abertura, ou clique em \"Gerar Agora\" para criá-lo agora."
            )
            .scaledFont(size: OmiType.body)
            .foregroundColor(Ink.secondary)
          } else {
            HStack {
              Spacer()
              VStack(spacing: OmiSpacing.sm) {
                ProgressView()
                Text("Gerando perfil…")
                  .scaledFont(size: OmiType.body)
                  .foregroundColor(Ink.secondary)
              }
              Spacer()
            }
            .padding(.vertical, OmiSpacing.xl)
          }
        }
      }
    }
    .task {
      // Try loading immediately (covers all restarts after first generation)
      if let profile = await AIUserProfileService.shared.getLatestProfile() {
        aiProfileId = profile.id
        aiProfileText = profile.profileText
        aiProfileGeneratedAt = profile.generatedAt
        aiProfileDataSourcesUsed = profile.dataSourcesUsed
        return
      }
      // No profile yet — first-ever generation may be in progress, poll briefly
      for _ in 0..<6 {
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        if let profile = await AIUserProfileService.shared.getLatestProfile() {
          aiProfileId = profile.id
          aiProfileText = profile.profileText
          aiProfileGeneratedAt = profile.generatedAt
          aiProfileDataSourcesUsed = profile.dataSourcesUsed
          return
        }
      }
    }
  }

  var statsSubsection: some View {
    VStack(spacing: OmiSpacing.xl) {
      settingsCard(settingId: "advanced.stats") {
        VStack(alignment: .leading, spacing: OmiSpacing.lg) {
          HStack(spacing: OmiSpacing.sm) {
            Image(systemName: "chart.bar")
              .scaledFont(size: OmiType.subheading)
              .foregroundColor(Ink.secondary)

            Text("Suas Estatísticas")
              .scaledFont(size: OmiType.subheading, weight: .medium)
              .foregroundColor(Ink.primary)

            Spacer()
          }

          GlassSeparator()

          if let stats = advancedStats {
            statRow(label: "Conversas", value: stats.conversations)
            statRow(label: "Apps Instalados", value: stats.appsInstalled)
            statRow(label: "Capturas de Tela", value: stats.screenshotsTotal)
            statRow(label: "Sessões de Foco", value: stats.focusSessions)
            statRow(label: "Tarefas (A fazer)", value: stats.tasksTodo)
            statRow(label: "Tarefas (Concluídas)", value: stats.tasksDone)
            statRow(label: "Tarefas (Removidas)", value: stats.tasksDeleted)
            statRow(label: "Metas", value: stats.goalsCount)
            statRow(label: "Memórias", value: stats.memoriesTotal)
          } else if isLoadingStats {
            statRowLoading(label: "Conversas")
            statRowLoading(label: "Apps Instalados")
            statRowLoading(label: "Capturas de Tela")
            statRowLoading(label: "Sessões de Foco")
            statRowLoading(label: "Tarefas (A fazer)")
            statRowLoading(label: "Tarefas (Concluídas)")
            statRowLoading(label: "Tarefas (Removidas)")
            statRowLoading(label: "Metas")
            statRowLoading(label: "Memórias")
          } else {
            Text("Não foi possível carregar as estatísticas")
              .scaledFont(size: OmiType.body)
              .foregroundColor(Ink.secondary)
          }
        }
      }
    }
    .task {
      await loadAdvancedStats()
    }
  }

  var featureTiersSubsection: some View {
    VStack(spacing: OmiSpacing.xl) {
      settingsCard(settingId: "advanced.featuretiers") {
        VStack(alignment: .leading, spacing: OmiSpacing.lg) {
          HStack(spacing: OmiSpacing.sm) {
            Image(systemName: "lock.shield")
              .scaledFont(size: OmiType.subheading)
              .foregroundColor(Ink.secondary)

            Text("Níveis de Recursos")
              .scaledFont(size: OmiType.subheading, weight: .medium)
              .foregroundColor(Ink.primary)

            Spacer()
          }

          GlassSeparator()

          // Tier picker — radio-style selector
          VStack(alignment: .leading, spacing: OmiSpacing.xs) {
            tierPickerRow(tier: 0, label: "Mostrar Todos os Recursos", subtitle: "Libera tudo")
            tierPickerRow(tier: 1, label: "Nível 1", subtitle: "Conversas + Rewind")
            tierPickerRow(tier: 2, label: "Nível 2", subtitle: "+ Memórias (100 memórias)")
            tierPickerRow(tier: 3, label: "Nível 3", subtitle: "+ Tarefas (100 tarefas)")
            tierPickerRow(tier: 4, label: "Nível 4", subtitle: "+ Chat com IA (100 conversas)")
            tierPickerRow(
              tier: 5, label: "Nível 5", subtitle: "+ Início (200 conversas + 2 mil capturas)")
            tierPickerRow(tier: 6, label: "Nível 6", subtitle: "+ Apps (300 conversas)")
          }

          if currentTierLevel > 0 {
            GlassSeparator()

            Text("Progresso")
              .scaledFont(size: OmiType.subheading, weight: .semibold)
              .foregroundColor(Ink.secondary)

            // Tier 1 — always unlocked
            tierFeatureRow(
              tier: 1, name: "Conversas + Rewind",
              requirement: "Sempre liberado",
              progress: nil, unlocked: true
            )

            // Tier 2 — 100 memories
            tierFeatureRow(
              tier: 2, name: "Memórias",
              requirement: "100 memórias",
              progress: advancedStats.map { "\($0.memoriesTotal) / 100" },
              unlocked: currentTierLevel >= 2
            )

            // Tier 3 — 100 tasks
            tierFeatureRow(
              tier: 3, name: "Tarefas",
              requirement: "100 tarefas (a fazer + concluídas)",
              progress: advancedStats.map { "\($0.tasksTodo + $0.tasksDone) / 100" },
              unlocked: currentTierLevel >= 3
            )

            // Tier 4 — 100 conversations
            tierFeatureRow(
              tier: 4, name: "Chat com IA",
              requirement: "100 conversas",
              progress: advancedStats.map { "\($0.conversations) / 100" },
              unlocked: currentTierLevel >= 4
            )

            // Tier 5 — 200 conversations + 2,000 screenshots
            tierFeatureRow(
              tier: 5, name: "Início",
              requirement: "200 conversas + 2 mil capturas",
              progress: advancedStats.map {
                "\($0.conversations) / 200 conversas, \($0.screenshotsTotal) / 2.000 capturas"
              },
              unlocked: currentTierLevel >= 5
            )

            // Tier 6 — 300 conversations
            tierFeatureRow(
              tier: 6, name: "Apps",
              requirement: "300 conversas",
              progress: advancedStats.map { "\($0.conversations) / 300" },
              unlocked: currentTierLevel >= 6
            )
          }
        }
      }
    }
  }

}
