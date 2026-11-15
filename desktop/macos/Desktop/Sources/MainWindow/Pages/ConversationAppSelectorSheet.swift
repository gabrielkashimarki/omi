import OmiTheme
import SwiftUI

// MARK: - App Selector Sheet

struct AppSelectorSheet: View {
  @ObservedObject var picker: ConversationSummaryAppPicker
  let isLoading: Bool
  let processingAppId: String?
  /// App behind the current primary summary (apps_results[0]); the row shows a
  /// checkmark so the picker opens on the active summarization app.
  var selectedAppId: String? = nil
  /// Locally mirrored preferred app; its row is badged "Default".
  var preferredAppId: String? = nil
  let onSelect: (OmiApp) -> Void
  var onSetPreferred: ((OmiApp) -> Void)? = nil
  let onBrowseApps: () -> Void
  let onDismiss: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      // Header
      HStack {
        Text("Selecionar app")
          .scaledFont(size: OmiType.subheading, weight: .semibold)
          .foregroundColor(Ink.primary)

        Spacer()

        DismissButton(action: onDismiss)
      }
      .padding()

      Divider()
        .background(Ink.rowFillHover)

      if picker.phase == .ready && !picker.apps.isEmpty {
        HStack(spacing: OmiSpacing.sm) {
          Image(systemName: "magnifyingglass")
            .foregroundStyle(Ink.secondary)
            .accessibilityHidden(true)
          TextField("Buscar apps instalados", text: $picker.searchText)
            .textFieldStyle(.plain)
            .accessibilityLabel("Buscar apps de resumo instalados")
            .accessibilityIdentifier("summary-app-search")
        }
        .padding(OmiSpacing.md)
      }

      switch picker.phase {
      case .idle, .loading:
        GlassLoadingState(label: "Carregando apps de resumo instalados…")
      case .failed:
        GlassErrorState(title: "Não foi possível carregar os apps", retry: { Task { await picker.load() } })
      case .ready where picker.apps.isEmpty:
        GlassEmptyState(
          systemImage: "square.grid.2x2", title: "Nenhum app de resumo instalado",
          message: "Instale um app de resumo para usar nesta conversa"
        ) {
          Button("Explorar apps", action: onBrowseApps)
            .buttonStyle(OmiButtonStyle(.primary, size: .compact))
        }
      case .ready where picker.visibleApps.isEmpty:
        GlassEmptyState(
          systemImage: "magnifyingglass", title: "Nenhum app encontrado",
          message: "Tente outro nome ou autor"
        ) {
          Button("Limpar busca") { picker.searchText = "" }
            .buttonStyle(OmiButtonStyle(.secondary, size: .compact))
        }
      case .ready:
        ScrollView {
          LazyVStack(spacing: OmiSpacing.hairline) {
            ForEach(picker.visibleApps) { app in
              AppSelectorRow(
                app: app,
                isSelected: selectedAppId == app.id,
                isPreferred: preferredAppId == app.id,
                isLoading: isLoading && processingAppId == app.id,
                onSelect: { onSelect(app) },
                onSetPreferred: onSetPreferred == nil ? nil : { onSetPreferred?(app) }
              )
            }
          }
          .padding(.horizontal, OmiSpacing.sm)
          .padding(.vertical, OmiSpacing.sm)
        }
      }
    }
    .frame(width: 320, height: 400)
    .background(Ink.surface)
  }
}

struct AppSelectorRow: View {
  let app: OmiApp
  let isSelected: Bool
  var isPreferred: Bool = false
  let isLoading: Bool
  let onSelect: () -> Void
  var onSetPreferred: (() -> Void)? = nil

  @State private var isHovering = false

  var body: some View {
    Button(action: onSelect) {
      HStack(spacing: OmiSpacing.md) {
        AsyncImage(url: URL(string: app.image)) { phase in
          switch phase {
          case .success(let image):
            image
              .resizable()
              .aspectRatio(contentMode: .fill)
          default:
            RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius)
              .fill(Ink.rowFillHover)
          }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius))

        VStack(alignment: .leading, spacing: OmiSpacing.hairline) {
          Text(app.name)
            .scaledFont(size: OmiType.body, weight: .medium)
          HStack(spacing: OmiSpacing.xxs) {
            Text(app.author)
              .scaledFont(size: OmiType.caption)
              .foregroundColor(Ink.secondary)

            if isPreferred {
              Image(systemName: "star.fill")
                .scaledFont(size: OmiType.micro)
                .foregroundColor(PageGlass.starred)
              Text("Padrão")
                .scaledFont(size: OmiType.micro)
                .foregroundColor(Ink.secondary)
            }
          }
        }

        Spacer()

        if isLoading {
          ProgressView()
            .scaleEffect(0.7)
        } else if isSelected {
          Image(systemName: "checkmark.circle.fill")
            .scaledFont(size: OmiType.heading)
            .foregroundColor(Ink.primary)
        }
      }
      .padding(.horizontal, OmiSpacing.md)
      .padding(.vertical, OmiSpacing.sm)
      .background(
        RoundedRectangle(cornerRadius: OmiChrome.smallControlRadius)
          .fill(isSelected || isHovering ? Ink.rowFillHover : Color.clear)
      )
    }
    .buttonStyle(.plain)
    .disabled(isLoading)
    .onHover { isHovering = $0 }
    .accessibilityValue(
      [isSelected ? "Selecionado" : nil, isPreferred ? "Padrão" : nil]
        .compactMap { $0 }
        .joined(separator: ", ")
    )
    // macOS analog of mobile's swipe-to-set-default: right-click a row to pin
    // the preferred summarization app for future conversations.
    .contextMenu {
      if let onSetPreferred {
        Button {
          onSetPreferred()
        } label: {
          Label(
            isPreferred ? "App padrão" : "Definir como padrão",
            systemImage: isPreferred ? "star.fill" : "star"
          )
        }
        .disabled(isPreferred)
      }
    }
  }
}
