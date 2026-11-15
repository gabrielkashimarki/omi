import Combine
import OmiTheme
import Sparkle
import SwiftUI
import UniformTypeIdentifiers
import WebKit

extension SettingsContentView {
  var notificationsSection: some View {
    VStack(spacing: OmiSpacing.xl) {
      storefrontFeatureEntry(.proactiveAgent)
      // Notifications
      settingsCard(settingId: "notifications.settings") {
        VStack(alignment: .leading, spacing: OmiSpacing.lg) {
          HStack {
            settingsCardHeader(icon: "bell.badge.fill", title: "Notificações")

            Spacer()

            Toggle("", isOn: $notificationsEnabled)
              .toggleStyle(OmiToggleStyle())
              .labelsHidden()
              .onChange(of: notificationsEnabled) { _, newValue in
                updateNotificationSettings(enabled: newValue)
              }
          }

          Text("Controle com que frequência você recebe notificações")
            .scaledFont(size: OmiType.body)
            .foregroundColor(Ink.secondary)

          if notificationsEnabled {
            GlassSeparator()

            notificationFrequencySlider(settingId: "notifications.frequency")

            GlassSeparator()

            // Sits with the frequency slider because it answers the same question — how
            // often may Omi interrupt — but for a bounded window rather than forever. The
            // floating bar's "Hide for 2 hours" is deliberately not this: that hides the
            // bar and still lets notifications through.
            settingRow(
              title: "Silenciar Notificações",
              subtitle: notificationSnoozeSubtitle,
              settingId: "notifications.snooze"
            ) {
              Menu {
                // Knowingly duplicated from `NotificationService.snoozeDurations`, and not
                // guarded by a test: `testOfferedDurationsAreSaneAndAscending` checks that
                // constant alone, so these three can drift from it silently. Change both
                // places together.
                //
                // A ForEach over the constant was tried and reverted after the release-mode
                // whole-module compile hit its 60 min job cap. The revert then ran 56m55s
                // with a compile-identical tree, against 51m on the head before it — so the
                // ForEach was not the cause; that lane is simply running at ~95% of its cap
                // and drifting up. Restoring it is safe on the merits and still a bad bet
                // until the lane has margin.
                Button("Por 1 hora") { applyNotificationSnooze(60 * 60) }
                Button("Por 4 horas") { applyNotificationSnooze(4 * 60 * 60) }
                Button("Por 8 horas") { applyNotificationSnooze(8 * 60 * 60) }
                Button("Até amanhã") {
                  NotificationService.snoozeNotificationsUntilTomorrow()
                  notificationsSnoozedUntil = NotificationService.currentSnoozeExpiry()
                }
                if notificationsSnoozedUntil != nil {
                  Divider()
                  Button("Reativar agora") {
                    NotificationService.endNotificationSnooze()
                    notificationsSnoozedUntil = nil
                  }
                }
              } label: {
                Text(notificationsSnoozedUntil == nil ? "Desligado" : "Silenciado")
              }
              .frame(width: 110)
            }

            GlassSeparator()

            // Sits under the master toggle and the frequency slider because both gate it:
            // frequency caps how often any proactive card is delivered, and this decides
            // whether focus nudges are generated at all.
            settingRow(
              title: "Notificações de Foco",
              subtitle: "Sugestões curtas no notch com base no que você está fazendo",
              settingId: "notifications.livesuggestions"
            ) {
              Toggle("", isOn: $liveSuggestionsEnabled)
                .toggleStyle(OmiToggleStyle())
                .labelsHidden()
                .onChange(of: liveSuggestionsEnabled) { _, newValue in
                  SuggestionAssistantSettings.shared.applyUserEnabledChange(newValue)
                }
            }

            GlassSeparator()

            settingRow(
              title: "Notificações de Tarefas",
              subtitle: "Permite interrupções quando uma tarefa precisa de atenção",
              settingId: "notifications.task"
            ) {
              Toggle("", isOn: $taskNotificationsEnabled)
                .toggleStyle(OmiToggleStyle())
                .labelsHidden()
                .onChange(of: taskNotificationsEnabled) { _, newValue in
                  TaskAssistantSettings.shared.notificationsEnabled = newValue
                  SettingsSyncManager.shared.pushPartialUpdate(
                    AssistantSettingsResponse(
                      task: TaskSettingsResponse(notificationsEnabled: newValue)))
                }
            }

            GlassSeparator()

            settingRow(
              title: "Notificações de Metas e Lembretes",
              subtitle: "Permite que metas e itens resgatados te notifiquem",
              settingId: "notifications.goalReminder"
            ) {
              Toggle("", isOn: $goalReminderNotificationsEnabled)
                .toggleStyle(OmiToggleStyle())
                .labelsHidden()
                .onChange(of: goalReminderNotificationsEnabled) { _, newValue in
                  NotificationService.goalReminderNotificationsEnabled = newValue

                }
            }

            GlassSeparator()

            settingRow(
              title: "Notificações de Resumo de Reunião",
              subtitle: "Após uma chamada, oferece copiar o link de compartilhamento ou enviar o resumo por e-mail aos participantes",
              settingId: "notifications.meetingsummary"
            ) {
              Toggle("", isOn: $meetingSummaryNotificationsEnabled)
                .toggleStyle(OmiToggleStyle())
                .labelsHidden()
                .onChange(of: meetingSummaryNotificationsEnabled) { _, newValue in
                  MeetingSummaryNotificationSettings.isEnabled = newValue
                }
            }

            GlassSeparator()

            settingRow(
              title: "Notificações de Memórias",
              subtitle: "Mostra uma notificação quando uma memória é extraída",
              settingId: "notifications.memory"
            ) {
              Toggle("", isOn: $memoryNotificationsEnabled)
                .toggleStyle(OmiToggleStyle())
                .labelsHidden()
                .onChange(of: memoryNotificationsEnabled) { _, newValue in
                  MemoryAssistantSettings.shared.applyUserSettingChange(.notificationsEnabled, value: newValue)
                  SettingsSyncManager.shared.pushPartialUpdate(
                    AssistantSettingsResponse(
                      memory: MemorySettingsResponse(notificationsEnabled: newValue)))
                }
            }

            GlassSeparator()

            // The fifth notification type. It lives inside the master gate for the
            // same reason as the other four: `IntegrationNudgeCoordinator.isEnabledNow`
            // requires notifications to be on, so showing this switched ON beside a
            // disabled master toggle would promise a feature that cannot run.
            // `@AppStorage` already persists to the key the coordinator reads;
            // a second writer on one key only invites drift.
            settingRow(
              title: "Notificações de Integrações",
              subtitle: "De vez em quando oferece conectar um app que o Omi pode usar (Gmail, Notion, ChatGPT)",
              settingId: "notifications.integrationsuggestions"
            ) {
              Toggle("", isOn: $integrationNudgesEnabled)
                .toggleStyle(OmiToggleStyle())
                .labelsHidden()
            }
          }
        }
      }

      // Daily Summary
      settingsCard(settingId: "notifications.dailysummary") {
        VStack(alignment: .leading, spacing: OmiSpacing.lg) {
          HStack {
            settingsCardHeader(icon: "text.badge.checkmark", title: "Resumo do Dia")

            Spacer()

            Toggle("", isOn: $dailySummaryEnabled)
              .toggleStyle(OmiToggleStyle())
              .labelsHidden()
              .onChange(of: dailySummaryEnabled) { _, newValue in
                updateDailySummarySettings(enabled: newValue)
              }
          }

          Text("Receba um resumo diário das suas conversas e atividades")
            .scaledFont(size: OmiType.body)
            .foregroundColor(Ink.secondary)

          if let dailySummaryEnabledError {
            Text(dailySummaryEnabledError)
              .scaledFont(size: OmiType.caption)
              .foregroundColor(Ink.errorRed)
              .accessibilityIdentifier("notifications-dailysummary-save-error")
          }

          if dailySummaryEnabled {
            GlassSeparator()

            settingRow(
              title: "Horário do Resumo", subtitle: "Quando enviar seu resumo do dia (só a hora)",
              settingId: "notifications.summarytime"
            ) {
              DatePicker(
                "",
                selection: $dailySummaryTime,
                displayedComponents: .hourAndMinute
              )
              .datePickerStyle(.stepperField)
              .labelsHidden()
              .fixedSize()
              .onChange(of: dailySummaryTime) { _, selectedTime in
                // Storage is hour-only; snap minutes to :00 in the control so 20:45 never
                // appears as a saved value that reopens as 20:00.
                let canonical = SettingsControlMetrics.canonicalizeDailySummaryTime(selectedTime)
                if canonical != selectedTime {
                  dailySummaryTime = canonical
                }
                let hour = SettingsControlMetrics.dailySummaryHour(from: canonical)
                guard hour != dailySummaryHour else { return }
                dailySummaryHour = hour
                updateDailySummarySettings(hour: hour)
              }
            }

            GlassSeparator()

            settingRow(
              title: "Profundidade do Resumo",
              subtitle: "Escolha quanto detalhe os próximos resumos do dia incluem",
              settingId: "notifications.recapdepth"
            ) {
              HStack(spacing: OmiSpacing.sm) {
                if dailySummaryDepthSaving {
                  ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Salvando profundidade do resumo")
                }
                SettingsMenuPicker(selection: $dailySummaryDepth) {
                  Text("Breve").tag(DailySummaryDepth.brief)
                  Text("Normal").tag(DailySummaryDepth.normal)
                  Text("Reflexão Profunda").tag(DailySummaryDepth.deep)
                }
                .frame(minWidth: 155)
                .disabled(dailySummaryDepthSaving)
                .onChange(of: dailySummaryDepth) { _, depth in
                  updateDailySummaryDepth(depth)
                }
              }
            }

            if let dailySummaryDepthError {
              Text(dailySummaryDepthError)
                .scaledFont(size: OmiType.caption)
                .foregroundColor(Ink.errorRed)
                .accessibilityIdentifier("recap-depth-save-error")
            }
          }
        }
      }

    }
    // These three toggles are seeded from their local singletons when the pane is constructed,
    // but `loadBackendSettings()` then runs `SettingsSyncManager.syncFromServer()`, which is
    // server-authoritative and rewrites those same singletons underneath us. Without this the
    // switches kept painting the pre-sync values — a per-device answer to a per-account
    // question — until the next relaunch. The sync manager already announces itself; this is
    // the pane agreeing to listen.
    .onReceive(NotificationCenter.default.publisher(for: .assistantSettingsDidSyncFromServer)) { _ in
      syncNotificationTogglesFromAssistantSettings()
    }
    .onReceive(NotificationCenter.default.publisher(for: .proactiveNotificationSnoozeDidChange)) { _ in
      refreshNotificationSnoozeState()
    }
    .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
      refreshNotificationSnoozeState()
    }
  }

  /// Re-reads the assistant notification toggles from their stores. A sync that agrees with the
  /// pane assigns nothing, so the common case does not re-enter the `onChange` handlers above; a
  /// sync that corrects the pane does, and the resulting partial update restates the value the
  /// server just supplied, which is idempotent.
  func syncNotificationTogglesFromAssistantSettings() {
    taskNotificationsEnabled = TaskAssistantSettings.shared.notificationsEnabled
    goalReminderNotificationsEnabled = NotificationService.goalReminderNotificationsEnabled
    memoryNotificationsEnabled = MemoryAssistantSettings.shared.notificationsEnabled
  }

  // MARK: - Privacy Section

  var privacySection: some View {
    VStack(spacing: OmiSpacing.xl) {
      settingsCard(settingId: "privacy.siri") {
        HStack(spacing: OmiSpacing.lg) {
          SettingsIconTile(symbol: "sparkles")
          VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
            Text("Usar o Omi com a Siri e o Apple Intelligence")
              .scaledFont(size: OmiType.subheading, weight: .semibold)
              .foregroundColor(Ink.primary)
            Text("Deixa resumos de conversas, memórias e tarefas disponíveis para a Siri neste Mac")
              .scaledFont(size: OmiType.body)
              .foregroundColor(Ink.secondary)
          }
          Spacer()
          Toggle(
            "",
            isOn: Binding(
              get: { SiriIntegrationSettings.isEnabled },
              set: { enabled in
                SiriIntegrationSettings.isEnabled = enabled
                if #available(macOS 15.4, *) {
                  SiriIndexHooks.ownerChanged()
                }
              }
            )
          )
          .toggleStyle(OmiToggleStyle())
          .labelsHidden()
        }
      }

      // Data Controls
      settingsCard(settingId: "privacy.storerecordings") {
        VStack(alignment: .leading, spacing: OmiSpacing.lg) {
          settingsCardHeader(icon: "shield", title: "Controle de Dados")

          privacyToggleRow(
            icon: "mic.fill",
            title: "Armazenar Gravações",
            subtitle: "Permite que o Omi armazene gravações de áudio das suas conversas",
            isOn: $recordingPermissionEnabled,
            errorText: recordingPermissionError
          ) { newValue in
            updateRecordingPermission(newValue)
          }

          GlassSeparator()

          privacyToggleRow(
            icon: "cloud.fill",
            title: "Sincronização em Nuvem Privada",
            subtitle: "Envie suas gravações para o seu próprio armazenamento na nuvem",
            isOn: $privateCloudSyncEnabled,
            errorText: privateCloudSyncError
          ) { newValue in
            updatePrivateCloudSync(newValue)
          }

          GlassSeparator()

          settingRow(
            title: "Exportar Todos os Dados",
            subtitle: "Baixe uma cópia JSON dos dados da sua conta",
            settingId: "privacy.exportdata"
          ) {
            Button("Exportar Todos os Dados…") {
              dataExportModel.startExport()
            }
            .buttonStyle(OmiButtonStyle(.secondary, size: .compact))
            .disabled(dataExportModel.isExporting)
            .accessibilityIdentifier("privacy.exportdata")
          }

          AccountDataExportView(model: dataExportModel)
        }
      }

      // Encryption
      settingsCard(settingId: "privacy.encryption") {
        VStack(alignment: .leading, spacing: OmiSpacing.md) {
          settingsCardHeader(icon: "shield.lefthalf.filled", title: "Criptografia")

          HStack(spacing: OmiSpacing.sm) {
            Image(systemName: "checkmark.circle.fill")
              .scaledFont(size: OmiType.caption)
              .foregroundColor(Ink.listeningGreen)
              .frame(width: 20, alignment: .leading)

            Text("Criptografia no servidor")
              .scaledFont(size: OmiType.body)
              .foregroundColor(Ink.secondary)

            Text("Ativa")
              .scaledFont(size: OmiType.micro, weight: .semibold)
              .foregroundColor(Ink.listeningGreen)
              .padding(.horizontal, OmiSpacing.xxs)
              .padding(.vertical, OmiSpacing.hairline)
              .background(Ink.listeningGreen.opacity(0.15))
              .cornerRadius(OmiChrome.stripRadius)
          }

          Text("Seus dados são criptografados e armazenados com segurança na infraestrutura do Google Cloud.")
            .scaledFont(size: OmiType.caption)
            .foregroundColor(Ink.secondary)
        }
      }

      // What We Track
      settingsCard(settingId: "privacy.tracking") {
        VStack(alignment: .leading, spacing: OmiSpacing.md) {
          Button(action: {
            OmiMotion.withGated(.easeInOut(duration: 0.2)) {
              isTrackingExpanded.toggle()
            }
          }) {
            HStack(spacing: OmiSpacing.sm) {
              Image(systemName: "list.bullet")
                .scaledFont(size: OmiType.body)
                .foregroundColor(Ink.secondary)
                .frame(width: 20)

              Text("O Que Monitoramos")
                .scaledFont(size: OmiType.body, weight: .medium)
                .foregroundColor(Ink.primary)

              Spacer()

              Image(systemName: "chevron.right")
                .scaledFont(size: OmiType.caption, weight: .semibold)
                .foregroundColor(Ink.secondary)
                .rotationEffect(.degrees(isTrackingExpanded ? 90 : 0))
            }
          }
          .buttonStyle(.plain)

          if isTrackingExpanded {
            VStack(alignment: .leading, spacing: OmiSpacing.xs) {
              trackingItem("Etapas da introdução concluídas")
              trackingItem("Mudanças nos ajustes")
              trackingItem("Instalações e uso de apps")
              trackingItem("Eventos de processamento de transcrição")
              trackingItem("Criação e atualização de conversas")
              trackingItem("Eventos de extração de memórias")
              trackingItem("Interações no chat")
              trackingItem("Criação do perfil de voz")
              trackingItem("Eventos de sessões de foco")
              trackingItem("Eventos de abrir/fechar o app")
            }
            .transition(.opacity)
          }
        }
      }

      // Privacy Guarantees
      settingsCard(settingId: "privacy.privacy") {
        VStack(alignment: .leading, spacing: OmiSpacing.sm) {
          HStack(spacing: OmiSpacing.sm) {
            Image(systemName: "hand.raised.fill")
              .scaledFont(size: OmiType.body)
              .foregroundColor(Ink.secondary)
              .frame(width: 20)

            Text("Garantias de Privacidade")
              .scaledFont(size: OmiType.body, weight: .medium)
              .foregroundColor(Ink.primary)
          }

          VStack(alignment: .leading, spacing: OmiSpacing.xs) {
            privacyBullet("Monitoramento anônimo com IDs gerados aleatoriamente")
            privacyBullet("Nenhuma informação pessoal armazenada nas análises")
            privacyBullet("Os dados nunca são vendidos nem compartilhados com terceiros")
            privacyBullet("Desative o monitoramento a qualquer momento")
          }
        }
      }
    }
  }

  // MARK: - Account Section

}

extension SettingsContentView {
  /// Reads the live expiry rather than the cached state so a snooze that lapsed while
  /// Settings sat open is reported as off.
  var notificationSnoozeSubtitle: String {
    guard let until = NotificationService.currentSnoozeExpiry(), until > Date() else {
      return "Pausa sugestões e lembretes por um tempo"
    }
    let formatter = DateFormatter()
    formatter.timeStyle = .short
    formatter.dateStyle = .none
    let time = formatter.string(from: until)
    // "Até amanhã" lands on another calendar day, where a bare time is ambiguous —
    // 9:00 AM tomorrow and 9:00 AM today read identically.
    guard Calendar.current.isDateInToday(until) else {
      return "Silenciado até amanhã às \(time)"
    }
    return "Silenciado até \(time)"
  }

  func applyNotificationSnooze(_ duration: TimeInterval) {
    NotificationService.snoozeNotifications(for: duration)
    refreshNotificationSnoozeState()
  }

  func refreshNotificationSnoozeState(now: Date = Date()) {
    guard let expiry = NotificationService.currentSnoozeExpiry(), expiry > now else {
      notificationsSnoozedUntil = nil
      return
    }
    notificationsSnoozedUntil = expiry
  }
}
