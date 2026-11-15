import OmiTheme
import SwiftUI

struct GmailAccountPickerView: View {
  let accounts: [GmailAccountOption]
  let selectedCookiePath: String?
  let hasMadeChoice: Bool
  let onSelect: (String?, String) -> Void
  let onCancel: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: OmiSpacing.md) {
      HStack {
        Text("Conta do Gmail")
          .inkStyle(InkType.firstTitle, color: Ink.primary)
        Spacer()
        Button("Cancelar", action: onCancel)
          .buttonStyle(.plain)
          .inkStyle(InkType.buttonLabel, color: Ink.secondary)
      }

      Button {
        onSelect(nil, "Automático")
      } label: {
        HStack {
          VStack(alignment: .leading, spacing: OmiSpacing.hairline) {
            Text("Automático")
              .inkStyle(InkType.rowCopy, color: Ink.primary)
            Text("Primeira conta legível do navegador")
              .inkStyle(InkType.statusLabel, color: Ink.secondary)
          }
          Spacer()
          // Only an explicit choice may show the checkmark: before any
          // selection, selectedCookiePath is nil but the user has not chosen
          // Automatic, and showing it as pre-selected invites a dismiss that
          // would strand the onboarding wait.
          if hasMadeChoice && selectedCookiePath == nil {
            Image(systemName: "checkmark")
              .foregroundStyle(Ink.accent)
          }
        }
      }
      .buttonStyle(.plain)

      Divider()

      ScrollView {
        ForEach(accounts) { account in
          Button {
            onSelect(account.id, accountLabel(account))
          } label: {
            HStack {
              VStack(alignment: .leading, spacing: OmiSpacing.hairline) {
                Text(account.browserName)
                  .inkStyle(InkType.rowCopy, color: Ink.primary)
                Text(account.email ?? "Conta desconhecida")
                  .inkStyle(InkType.statusLabel, color: Ink.secondary)
              }
              Spacer()
              if selectedCookiePath == account.id {
                Image(systemName: "checkmark")
                  .foregroundStyle(Ink.accent)
              }
            }
          }
          .buttonStyle(.plain)
        }
      }
      .frame(maxHeight: 280)
    }
    .padding(OmiSpacing.lg)
    .frame(width: 400)
    .background(Ink.surface)
  }

  private func accountLabel(_ account: GmailAccountOption) -> String {
    account.email.map { "\($0) (\(account.browserName))" } ?? account.browserName
  }
}
