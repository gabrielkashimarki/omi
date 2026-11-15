import OmiTheme
import Sparkle
import SwiftUI
import UniformTypeIdentifiers
import WebKit

extension SettingsContentView {
  var accountSection: some View {
    VStack(spacing: OmiSpacing.xl) {
      settingsCard(settingId: "account.account") {
        VStack(alignment: .leading, spacing: OmiSpacing.md) {
          // `account.signout` is its own search result ("Sign Out / sign out of
          // your omi account"), so it needs its own anchor. Without one the
          // search jump selected the pane and then scrolled to nothing.
          settingsGroup(settingId: "account.signout") {
            HStack(spacing: OmiSpacing.lg) {
              Image(systemName: "person.circle.fill")
                .scaledFont(size: OmiType.hero)
                .foregroundColor(Ink.secondary)

              VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
                Text(
                  AuthService.shared.displayName.isEmpty ? "Usuário" : AuthService.shared.displayName
                )
                .scaledFont(size: OmiType.subheading, weight: .semibold)
                .foregroundColor(Ink.primary)

                if let email = AuthState.shared.userEmail {
                  Text(email)
                    .scaledFont(size: OmiType.body)
                    .foregroundColor(Ink.secondary)
                }
              }

              Spacer()

              Button("Sair") {
                appState.stopTranscription()
                ProactiveAssistantsPlugin.shared.stopMonitoring(reason: .signOut)
                Task {
                  try? await AuthService.shared.signOut()
                }
              }
              // Secondary: signing out is reversible and is not what this page is for, so it is not
              // the loudest control on it.
              .buttonStyle(OmiButtonStyle(.secondary, size: .compact))
              .disabled(isDeletingAccount)
            }
          }

          GlassSeparator()

          HStack(alignment: .center, spacing: OmiSpacing.lg) {
            VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
              Text("Apagar Conta e Dados")
                .scaledFont(size: OmiType.subheading, weight: .semibold)
                .foregroundColor(Ink.errorRed)

              Text(
                "Apaga permanentemente os dados do servidor, limpa os dados locais desta conta, reinicia a introdução e desconecta você."
              )
              .scaledFont(size: OmiType.body)
              .foregroundColor(Ink.secondary)
            }

            Spacer()

            Button(action: {
              AnalyticsManager.shared.deleteAccountClicked()
              showDeleteAccountAlert = true
            }) {
              if isDeletingAccount {
                ProgressView()
                  .controlSize(.small)
              } else {
                Text("Apagar")
                  .scaledFont(size: OmiType.body, weight: .semibold)
              }
            }
            .buttonStyle(OmiButtonStyle(.destructive, size: .compact))
            .disabled(isDeletingAccount)
          }

          if let deleteAccountError {
            Text(deleteAccountError)
              .scaledFont(size: OmiType.caption)
              .foregroundColor(SettingsInk.notice)
          }
        }
      }
      .shellConfirmation(
        isPresented: $showDeleteAccountAlert,
        title: "Apagar Conta e Dados?",
        message: "Isso não pode ser desfeito. Sua conta, o histórico do chat e todos os dados do servidor serão apagados permanentemente. "
          + "Os dados locais desta conta serão limpos e você voltará à introdução.",
        confirmTitle: "Apagar Permanentemente",
        onCancel: { AnalyticsManager.shared.deleteAccountCancelled() }
      ) {
        deleteAccountAndData()
      }

      //            settingsCard {
      //                HStack(spacing: OmiSpacing.lg) {
      //                    Image(systemName: "bolt.fill")
      //                        .scaledFont(size: OmiType.subheading)
      //                        .foregroundColor(SettingsInk.notice)
      //
      //                    VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
      //                        Text("Upgrade to Pro")
      //                            .scaledFont(size: OmiType.subheading, weight: .medium)
      //                            .foregroundColor(Ink.primary)
      //
      //                        Text("Unlock all features and unlimited usage")
      //                            .scaledFont(size: OmiType.body)
      //                            .foregroundColor(Ink.secondary)
      //                    }
      //
      //                    Spacer()
      //
      //                    Button("Upgrade") {
      //                        if let url = URL(string: "https://omi.me/pricing") {
      //                            NSWorkspace.shared.open(url)
      //                        }
      //                    }
      //                    .buttonStyle(.borderedProminent)
      //                    .tint(Ink.accent)
      //                }
      //            }
    }
  }

  // MARK: - Trial Countdown Card

  @ViewBuilder
  var trialCountdownCard: some View {
    if let trial = appState.trialMetadata, trial.trialStartedAt != nil, !trial.trialExpired {
      settingsCard(settingId: "planusage.trial") {
        VStack(alignment: .leading, spacing: OmiSpacing.md) {
          HStack(spacing: OmiSpacing.lg) {
            Image(systemName: "clock.fill")
              .scaledFont(size: OmiType.title)
              .foregroundColor(trialTimeColor(remaining: trial.trialRemainingSeconds))

            VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
              Text("Teste Premium Ativo")
                .scaledFont(size: OmiType.subheading, weight: .semibold)
                .foregroundColor(Ink.primary)

              Text(trialCountdownText(remaining: trial.trialRemainingSeconds))
                .scaledFont(size: OmiType.body)
                .foregroundColor(trialTimeColor(remaining: trial.trialRemainingSeconds))
            }

            Spacer()

            // Progress ring
            ZStack {
              Circle()
                .stroke(Ink.hairline, lineWidth: 3)
              Circle()
                .trim(from: 0, to: trialProgress(trial))
                .stroke(
                  trialTimeColor(remaining: trial.trialRemainingSeconds),
                  style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            }
            .frame(width: 32, height: 32)
          }

          GlassSeparator()

          VStack(alignment: .leading, spacing: OmiSpacing.sm) {
            Text("Incluído no seu teste")
              .scaledFont(size: OmiType.caption, weight: .semibold)
              .foregroundColor(Ink.secondary)

            trialFeatureRow(text: "Escuta e transcrição ilimitadas")
            trialFeatureRow(text: "Memórias e insights ilimitados")
            trialFeatureRow(text: "Perguntas no chat")
          }
        }
      }
    } else if let trial = appState.trialMetadata,
      trial.trialExpired
    {
      settingsCard(settingId: "planusage.trial-expired") {
        VStack(alignment: .leading, spacing: OmiSpacing.md) {
          HStack(spacing: OmiSpacing.lg) {
            Image(systemName: "exclamationmark.circle.fill")
              .scaledFont(size: OmiType.title)
              .foregroundColor(SettingsInk.notice)

            VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
              Text("Teste Encerrado")
                .scaledFont(size: OmiType.subheading, weight: .semibold)
                .foregroundColor(Ink.primary)

              Text("Faça upgrade para manter o acesso ilimitado")
                .scaledFont(size: OmiType.body)
                .foregroundColor(Ink.secondary)
            }

            Spacer()
          }

          GlassSeparator()

          Button(action: {
            selectedPlanIdForCheckout = omiProPlanId
          }) {
            Text("Ver Planos")
              .scaledFont(size: OmiType.body, weight: .semibold)
          }
          .buttonStyle(OmiButtonStyle(.primary, size: .compact))
        }
      }
    }
  }

  func trialFeatureRow(text: String) -> some View {
    HStack(spacing: OmiSpacing.sm) {
      ZStack {
        Circle()
          .fill(Ink.rowFill)
          .frame(width: 18, height: 18)
        Image(systemName: "checkmark")
          .scaledFont(size: OmiType.micro, weight: .bold)
          .foregroundColor(Ink.secondary)
      }
      Text(text)
        .scaledFont(size: OmiType.body, weight: .medium)
        .foregroundColor(Ink.secondary)
    }
  }

  func trialCountdownText(remaining: Int) -> String {
    if remaining <= 0 { return "Expirado" }
    let hours = remaining / 3600
    let minutes = (remaining % 3600) / 60
    if hours >= 24 {
      let days = hours / 24
      let leftoverHours = hours % 24
      return "\(days)d \(leftoverHours)h restantes"
    }
    if hours > 0 {
      return "\(hours)h \(minutes)m restantes"
    }
    return "\(minutes)m restantes"
  }

  func trialTimeColor(remaining: Int) -> Color {
    if remaining <= 3600 { return SettingsInk.notice }  // < 1 hour: warning orange
    if remaining <= 24 * 3600 { return SettingsInk.notice }  // < 24 hours: yellow
    return Ink.listeningGreen  // plenty of time: green
  }

  func trialProgress(_ trial: TrialMetadataResponse) -> CGFloat {
    guard trial.trialDurationSeconds > 0 else { return 0 }
    return CGFloat(trial.trialRemainingSeconds) / CGFloat(trial.trialDurationSeconds)
  }

  // MARK: - Plan and Usage Section

  var planUsageSection: some View {
    VStack(spacing: OmiSpacing.xl) {
      trialCountdownCard

      if PlanStorefrontGate.sheetEnabled {
        storefrontPlanSection
      } else {
        settingsCard(settingId: "planusage.current") {
          VStack(alignment: .leading, spacing: OmiSpacing.md) {
            HStack(spacing: OmiSpacing.lg) {
              Image(systemName: "creditcard.fill")
                .scaledFont(size: OmiType.title)
                .foregroundColor(Ink.secondary)

              VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
                Text(currentPlanTitle)
                  .scaledFont(size: OmiType.subheading, weight: .semibold)
                  .foregroundColor(Ink.primary)

                Text(currentPlanSubtitle)
                  .scaledFont(size: OmiType.body)
                  .foregroundColor(Ink.secondary)
              }

              Spacer()

              if isLoadingSubscription {
                ProgressView()
                  .controlSize(.small)
              } else if hasPaidSubscription {
                CurrentPlanCardActions(
                  cancelAtPeriodEnd: userSubscription?.subscription.cancelAtPeriodEnd == true,
                  currentPriceId: userSubscription?.subscription.currentPriceId,
                  checkoutBusy: activeCheckoutPriceId != nil
                    && activeCheckoutPriceId == userSubscription?.subscription.currentPriceId,
                  portalBusy: isOpeningCustomerPortal,
                  onResubscribe: { startCheckout(for: $0) },
                  onManage: openCustomerPortal
                )
              } else {
                Button("Atualizar") {
                  loadSubscriptionInfo()
                }
                .buttonStyle(OmiButtonStyle(.primary, size: .compact))
                .disabled(isLoadingSubscription)
              }
            }

            if let periodText = currentPlanPeriodText {
              GlassSeparator()

              Text(periodText)
                .scaledFont(size: OmiType.caption)
                .foregroundColor(Ink.secondary)
            }

            if let confirmation = subscriptionConfirmation {
              Text(confirmation)
                .scaledFont(size: OmiType.caption, weight: .semibold)
                .foregroundColor(Ink.listeningGreen)
            }

            if let userSubscription {
              GlassSeparator()
              Text(TranscriptionAllowancePresentation.statusText(userSubscription.transcriptionAllowance))
                .scaledFont(size: OmiType.caption)
                .foregroundColor(Ink.secondary)
            }

            if let error = subscriptionError {
              Text(error)
                .scaledFont(size: OmiType.caption)
                .foregroundColor(SettingsInk.notice)
            }
          }
        }

        if let subscription = userSubscription?.subscription,
          subscription.deprecated == true
        {
          settingsCard(settingId: "planusage.deprecation") {
            VStack(alignment: .leading, spacing: OmiSpacing.md) {
              HStack(spacing: OmiSpacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                  .foregroundColor(SettingsInk.notice)
                  .scaledFont(size: OmiType.subheading)
                Text("Plano em Descontinuação")
                  .scaledFont(size: OmiType.subheading, weight: .semibold)
                  .foregroundColor(Ink.primary)
              }

              Text(
                subscription.deprecationMessage
                  ?? "Seu plano \(currentPlanTitle) está sendo descontinuado. Mude para o Omi Pro por \(omiProDeprecationFallbackPrice)."
              )
              .scaledFont(size: OmiType.body)
              .foregroundColor(Ink.secondary)
              .fixedSize(horizontal: false, vertical: true)

              Button(action: {
                selectedPlanIdForCheckout = omiProPlanId
              }) {
                Text("Mudar para o Omi Pro")
                  .scaledFont(size: OmiType.body, weight: .semibold)
              }
              .buttonStyle(OmiButtonStyle(.primary, size: .compact))
            }
          }
        }

        if shouldShowPlanPurchaseOptions {
          // Deliberately a `settingsGroup` and not a `settingsCard`: each plan tile draws its own
          // fill, corner and selected border, so wrapping the row in a card put a card inside a card
          // — two grounds, two radii and two borders for one block of content, against the one-card
          // recipe every other pane follows. The tiles *are* the cards; the group only carries the
          // `settingId` so the deep link still lands.
          settingsGroup(settingId: "planusage.purchase") {
            // All plan cards share the row width — no horizontal scrolling.
            HStack(alignment: .top, spacing: OmiSpacing.lg) {
              ForEach(subscriptionPlansForDisplay) { plan in
                subscriptionPlanCard(plan)
                  .frame(maxWidth: .infinity, alignment: .topLeading)
              }
            }
          }
        }
      }

      chatUsageQuotaCard

      overageCard

      byokPromoCard
    }
    .sheet(isPresented: $showOverageExplainer) {
      overageExplainerSheet
    }
    .onAppear {
      // The plan grid is part of this settings section, so this is a settings
      // impression, not a blocked purchase gate. Quota and usage-limit surfaces
      // keep their own sources.
      AnalyticsManager.shared.paywallOpened(
        source: "macos_settings_view",
        currentPlan: userSubscription?.subscription.plan.rawValue ?? "unknown")
    }
  }

  @ViewBuilder
  var overageCard: some View {
    if let info = overageInfo, info.isOveragePlan {
      settingsCard(settingId: "planusage.overage") {
        VStack(alignment: .leading, spacing: OmiSpacing.sm) {
          HStack(spacing: OmiSpacing.sm) {
            Image(
              systemName: info.excessQuestions > 0
                ? "dollarsign.circle.fill"
                : "checkmark.circle.fill"
            )
            .scaledFont(size: OmiType.heading)
            .foregroundColor(
              info.excessQuestions > 0
                ? SettingsInk.notice
                : Ink.listeningGreen)
            Text(
              info.excessQuestions > 0
                ? "Excedente por uso"
                : "Nenhum excedente neste ciclo ainda"
            )
            .scaledFont(size: OmiType.body, weight: .semibold)
            .foregroundColor(Ink.primary)
            Spacer()
            if info.excessQuestions > 0 {
              Text(String(format: "$%.2f", info.overageUsd))
                .scaledFont(size: OmiType.subheading, weight: .semibold)
                .foregroundColor(SettingsInk.notice)
                .monospacedDigit()
            }
          }

          if info.excessQuestions > 0 {
            Text(
              "Você passou \(info.excessQuestions) pergunta\(info.excessQuestions == 1 ? "" : "s") do limite de \(info.includedQuestions ?? 0) incluídas no seu plano. Cobraremos o excedente no fim do ciclo."
            )
            .scaledFont(size: OmiType.caption)
            .foregroundColor(Ink.secondary)
            .fixedSize(horizontal: false, vertical: true)
          } else {
            Text(
              "Se passar das \(info.includedQuestions ?? 0) perguntas incluídas, cobraremos o custo real do provedor + \(Int(info.markupPercent))%. Sem corte brusco."
            )
            .scaledFont(size: OmiType.caption)
            .foregroundColor(Ink.secondary)
            .fixedSize(horizontal: false, vertical: true)
          }

          Button(action: { showOverageExplainer = true }) {
            HStack(spacing: OmiSpacing.xxs) {
              Text(info.explainerTitle)
              Image(systemName: "info.circle")
            }
          }
          .buttonStyle(OmiButtonStyle(.primary, size: .compact))
        }
      }
    } else if isLoadingOverage && overageInfo == nil {
      // silent while loading — nothing to show
      EmptyView()
    }
  }

  var overageExplainerSheet: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: OmiSpacing.lg) {
        HStack {
          Text(overageInfo?.explainerTitle ?? "Como funciona a cobrança de excedente")
            .scaledFont(size: OmiType.heading, weight: .semibold)
            .foregroundColor(Ink.primary)
          Spacer()
          DismissButton(action: { showOverageExplainer = false })
        }

        Text(overageInfo?.explainerBody ?? "")
          .scaledFont(size: OmiType.body)
          .foregroundColor(Ink.secondary)
          .fixedSize(horizontal: false, vertical: true)

        if let info = overageInfo, info.isOveragePlan {
          GlassSeparator()
          VStack(alignment: .leading, spacing: OmiSpacing.sm) {
            Text("Seu ciclo atual")
              .scaledFont(size: OmiType.subheading, weight: .semibold)
              .foregroundColor(Ink.primary)
            overageExplainerRow("Perguntas usadas", value: "\(info.usedQuestions)")
            overageExplainerRow("Incluídas no plano", value: "\(info.includedQuestions ?? 0)")
            overageExplainerRow("Acima do limite", value: "\(info.excessQuestions)")
            overageExplainerRow(
              "Custo real do provedor",
              value: String(format: "$%.2f", info.realCostUsd)
            )
            overageExplainerRow(
              "Margem",
              value: String(format: "%.0f%%", info.markupPercent)
            )
            overageExplainerRow(
              "Excedente a cobrar",
              value: String(format: "$%.2f", info.overageUsd),
              emphasized: true
            )
          }
        }
      }
      .padding(OmiSpacing.xxl)
    }
    .frame(minWidth: 440, minHeight: 360)
  }

  func overageExplainerRow(_ label: String, value: String, emphasized: Bool = false) -> some View {
    HStack {
      Text(label)
        .scaledFont(size: OmiType.caption)
        .foregroundColor(Ink.secondary)
      Spacer()
      Text(value)
        .scaledFont(size: OmiType.caption, weight: emphasized ? .semibold : .regular)
        .foregroundColor(emphasized ? SettingsInk.notice : Ink.secondary)
        .monospacedDigit()
    }
  }

  @ViewBuilder
  var byokPromoCard: some View {
    settingsCard(settingId: "planusage.byok") {
      VStack(alignment: .leading, spacing: OmiSpacing.md) {
        HStack(spacing: OmiSpacing.md) {
          Image(systemName: "key.fill")
            .scaledFont(size: OmiType.heading)
            .foregroundColor(Ink.secondary)
          VStack(alignment: .leading, spacing: OmiSpacing.hairline) {
            Text(byokStatusTitle)
              .scaledFont(size: OmiType.subheading, weight: .semibold)
              .foregroundColor(Ink.primary)
            Text(byokUsageDescription)
              .scaledFont(size: OmiType.caption)
              .foregroundColor(Ink.secondary)
          }
          Spacer()
        }

        Button(action: openBYOKSettings) {
          Text(APIKeyService.isByokActive ? "Gerenciar Chaves" : "Adicionar Chaves")
            .scaledFont(size: OmiType.body, weight: .semibold)
        }
        .buttonStyle(OmiButtonStyle(.primary, size: .compact))
      }
    }
  }

  func openBYOKSettings() {
    selectedSection = .advanced
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
      highlightedSettingId = "advanced.devkeys.info"
    }
  }

  // MARK: - Chat Usage Quota Card

  // Anchored on `planusage.overview` ("Plan and Usage — subscription status and
  // usage limits"), not on `planusage.current`. Both cards carried
  // `planusage.current`, which put two views with the same SwiftUI `.id` in one
  // scroll container: the deep link was ambiguous and the search flash fired on
  // both. `planusage.overview` had no anchor at all, and this — the card that
  // shows the usage against the limit — is what that search result promises.
  @ViewBuilder
  var chatUsageQuotaCard: some View {
    if let quota = chatUsageQuota {
      settingsCard(settingId: "planusage.overview") {
        VStack(alignment: .leading, spacing: OmiSpacing.md) {
          HStack {
            Text("Uso neste mês")
              .scaledFont(size: OmiType.subheading, weight: .semibold)
              .foregroundColor(Ink.primary)
            Spacer()
            Text(chatUsageQuotaValueText(quota))
              .scaledFont(size: OmiType.body, weight: .medium)
              .foregroundColor(chatUsageBarColor(quota))
              .monospacedDigit()
          }

          ProgressView(value: min(quota.percent / 100.0, 1.0))
            .progressViewStyle(LinearProgressViewStyle(tint: chatUsageBarColor(quota)))
            .frame(height: 6)

          HStack {
            Text(chatUsageQuotaDescription(quota))
              .scaledFont(size: OmiType.caption)
              .foregroundColor(Ink.secondary)
            Spacer()
            if let resetText = chatUsageQuotaResetText(quota) {
              Text(resetText)
                .scaledFont(size: OmiType.caption)
                .foregroundColor(Ink.secondary)
            }
          }

          if !quota.allowed {
            // Neo / overage-enabled plans keep working past the cap (extra
            // usage accrues as overage). Show a softer message on those plans;
            // only show the hard "upgrade" copy on Free and other hard-capped
            // plans.
            if let info = overageInfo, info.isOveragePlan {
              Text("Você passou do limite incluído, e o uso extra é cobrado como excedente no fim do ciclo.")
                .scaledFont(size: OmiType.caption)
                .foregroundColor(SettingsInk.notice)
            } else {
              Text("Você atingiu o limite deste mês. Faça upgrade do plano ou espere até a próxima renovação.")
                .scaledFont(size: OmiType.caption)
                .foregroundColor(SettingsInk.notice)
            }
          } else if quota.percent >= 80.0 {
            Text("Você está perto do seu limite mensal.")
              .scaledFont(size: OmiType.caption)
              .foregroundColor(SettingsInk.notice)
          }
        }
      }
    } else if isLoadingChatUsage {
      settingsCard(settingId: "planusage.overview") {
        HStack {
          ProgressView().controlSize(.small)
          Text("Carregando uso…")
            .scaledFont(size: OmiType.body)
            .foregroundColor(Ink.secondary)
        }
      }
    }
  }

  func chatUsageQuotaValueText(_ q: APIClient.ChatUsageQuota) -> String {
    if q.unit == "cost_usd" {
      let limit = q.limit.map { String(format: "$%.0f", $0) } ?? "—"
      return String(format: "$%.2f / %@", q.used, limit)
    }
    let used = Int(q.used)
    let limit = q.limit.map { "\(Int($0))" } ?? "∞"
    return "\(used) / \(limit)"
  }

  func chatUsageQuotaDescription(_ q: APIClient.ChatUsageQuota) -> String {
    if q.unit == "cost_usd" {
      return "Gasto do chat no plano \(q.plan)"
    }
    return "Perguntas do chat no plano \(q.plan)"
  }

  func chatUsageQuotaResetText(_ q: APIClient.ChatUsageQuota) -> String? {
    guard let resetAt = q.resetAt else { return nil }
    let resetDate = Date(timeIntervalSince1970: TimeInterval(resetAt))
    let now = Date()
    let days = max(0, Int(resetDate.timeIntervalSince(now) / 86400))
    if days <= 0 {
      return "Renova hoje"
    }
    if days == 1 {
      return "Renova amanhã"
    }
    return "Renova em \(days) dias"
  }

  func chatUsageBarColor(_ q: APIClient.ChatUsageQuota) -> Color {
    if !q.allowed || q.percent >= 100.0 { return SettingsInk.notice }
    if q.percent >= 80.0 { return SettingsInk.notice }
    return Ink.accent
  }

  // MARK: - AI Chat Section

}
