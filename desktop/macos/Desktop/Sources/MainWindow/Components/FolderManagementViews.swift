import OmiTheme
import SwiftUI

// MARK: - Folder Colors

struct FolderColors {
  /// The indigo and violet swatches are gone from the picker: INV-UI-1 bans that hue anywhere in the
  /// UI, and a colour the *product* ships in a swatch grid is the UI choosing it, not the user. A
  /// folder already saved with either hex still renders its stored colour — the stored value is user
  /// data, and silently repainting someone's folders is a worse defect than the one being fixed.
  static let palette: [(name: String, hex: String)] = [
    ("Cinza", "#6B7280"),
    ("Vermelho", "#EF4444"),
    ("Laranja", "#F97316"),
    ("Âmbar", "#F59E0B"),
    ("Verde", "#22C55E"),
    ("Azul-petróleo", "#14B8A6"),
    ("Azul", "#3B82F6"),
    ("Rosa", "#EC4899"),
  ]
}

// MARK: - Folder Tabs Strip

struct FolderTabsStrip: View {
  @ObservedObject var appState: AppState
  var onCreateFolder: () -> Void
  var onEditFolder: (Folder) -> Void
  var onDeleteFolder: (Folder) -> Void

  @State private var isFilteringFolder: Bool = false

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: OmiSpacing.xs) {
        // "All" tab
        folderTab(
          label: "Todas",
          icon: "tray.2",
          isSelected: appState.selectedFolderId == nil && !appState.showStarredOnly
        ) {
          Task {
            isFilteringFolder = true
            await appState.setFolderFilter(nil)
            if appState.showStarredOnly {
              await appState.toggleStarredFilter()
            }
            isFilteringFolder = false
          }
        }

        // "Starred" tab
        folderTab(
          label: "Favoritas",
          icon: appState.showStarredOnly ? "star.fill" : "star",
          isSelected: appState.showStarredOnly
        ) {
          Task {
            isFilteringFolder = true
            await appState.toggleStarredFilter()
            isFilteringFolder = false
          }
        }

        // Folder tabs
        ForEach(appState.folders) { folder in
          let isSelected = appState.selectedFolderId == folder.id
          folderTab(
            label: folder.name,
            icon: nil,
            isSelected: isSelected
          ) {
            Task {
              isFilteringFolder = true
              if isSelected {
                await appState.setFolderFilter(nil)
              } else {
                await appState.setFolderFilter(folder.id)
              }
              isFilteringFolder = false
            }
          }
          .contextMenu {
            Button {
              onEditFolder(folder)
            } label: {
              Label("Editar", systemImage: "pencil")
            }
            Button(role: .destructive) {
              onDeleteFolder(folder)
            } label: {
              Label("Apagar", systemImage: "trash")
            }
          }
        }

        // "+" create button
        Button(action: onCreateFolder) {
          Image(systemName: "plus")
            .scaledFont(size: OmiType.caption, weight: .semibold)
            .foregroundColor(Ink.secondary)
            .frame(width: 26, height: 26)
            .background(
              RoundedRectangle(cornerRadius: OmiChrome.badgeRadius)
                .fill(Ink.rowFillHover.opacity(0.6))
            )
        }
        .buttonStyle(.plain)
      }
      .padding(.vertical, OmiSpacing.hairline)
    }
    .disabled(isFilteringFolder)
  }

  @ViewBuilder
  private func folderTab(
    label: String,
    icon: String?,
    isSelected: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: OmiSpacing.xxs) {
        if let icon = icon {
          Image(systemName: icon)
            .scaledFont(size: OmiType.caption)
        }
        Text(label)
          .scaledFont(size: OmiType.caption, weight: .medium)
          .lineLimit(1)
      }
      .foregroundColor(isSelected ? Ink.primary : Ink.secondary)
      .padding(.horizontal, OmiSpacing.sm)
      .padding(.vertical, OmiSpacing.xs)
      .glassChip(isActive: isSelected)
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Folder Form Sheet (Create / Edit)

struct FolderFormSheet: View {
  let folder: Folder?
  let onDismiss: () -> Void

  @EnvironmentObject var appState: AppState

  @State private var name: String = ""
  @State private var descriptionText: String = ""
  @State private var selectedColor: String = "#6B7280"
  @State private var isSaving: Bool = false

  private var isEditing: Bool { folder != nil }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Header
      HStack {
        Text(isEditing ? "Editar pasta" : "Nova pasta")
          .scaledFont(size: OmiType.subheading, weight: .semibold)
          .foregroundColor(Ink.primary)
        Spacer()
        DismissButton(action: onDismiss)
      }
      .padding(OmiSpacing.xl)

      Divider().background(Ink.rowFillHover)

      VStack(alignment: .leading, spacing: OmiSpacing.lg) {
        // Name field
        VStack(alignment: .leading, spacing: OmiSpacing.xs) {
          Text("Nome")
            .scaledFont(size: OmiType.caption, weight: .medium)
            .foregroundColor(Ink.secondary)
          TextField("Nome da pasta", text: $name)
            .textFieldStyle(.plain)
            .scaledFont(size: OmiType.body)
            .foregroundColor(Ink.primary)
            .padding(.horizontal, OmiSpacing.sm)
            .padding(.vertical, OmiSpacing.sm)
            .background(
              RoundedRectangle(cornerRadius: OmiChrome.elementRadius)
                .fill(Ink.rowFillHover.opacity(0.5))
            )
            .overlay(
              RoundedRectangle(cornerRadius: OmiChrome.elementRadius)
                .stroke(Ink.separator, lineWidth: 1)
            )
        }

        // Description field
        VStack(alignment: .leading, spacing: OmiSpacing.xs) {
          Text("Descrição")
            .scaledFont(size: OmiType.caption, weight: .medium)
            .foregroundColor(Ink.secondary)
          TextField("Descrição (opcional)", text: $descriptionText)
            .textFieldStyle(.plain)
            .scaledFont(size: OmiType.body)
            .foregroundColor(Ink.primary)
            .padding(.horizontal, OmiSpacing.sm)
            .padding(.vertical, OmiSpacing.sm)
            .background(
              RoundedRectangle(cornerRadius: OmiChrome.elementRadius)
                .fill(Ink.rowFillHover.opacity(0.5))
            )
            .overlay(
              RoundedRectangle(cornerRadius: OmiChrome.elementRadius)
                .stroke(Ink.separator, lineWidth: 1)
            )
        }

        // Color picker
        VStack(alignment: .leading, spacing: OmiSpacing.xs) {
          Text("Cor")
            .scaledFont(size: OmiType.caption, weight: .medium)
            .foregroundColor(Ink.secondary)

          LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(32), spacing: OmiSpacing.sm), count: 5), spacing: OmiSpacing.sm
          ) {
            ForEach(FolderColors.palette, id: \.hex) { item in
              let isSelected = selectedColor == item.hex
              Button(action: {
                selectedColor = item.hex
              }) {
                Circle()
                  .fill(Color(hex: item.hex) ?? Ink.secondary)
                  .frame(width: 28, height: 28)
                  .overlay(
                    Circle()
                      .stroke(Ink.surface, lineWidth: isSelected ? 2 : 0)
                      .padding(OmiSpacing.hairline)
                  )
                  .overlay(
                    Circle()
                      .stroke(isSelected ? (Color(hex: item.hex) ?? Ink.secondary) : Color.clear, lineWidth: 2)
                  )
              }
              .buttonStyle(.plain)
            }
          }
        }
      }
      .padding(OmiSpacing.xl)

      Divider().background(Ink.rowFillHover)

      // Action buttons
      HStack {
        Spacer()
        Button("Cancelar") {
          onDismiss()
        }
        .buttonStyle(.plain)
        .foregroundColor(Ink.secondary)
        .padding(.horizontal, OmiSpacing.lg)
        .padding(.vertical, OmiSpacing.sm)

        Button(action: save) {
          if isSaving {
            ProgressView()
              .scaleEffect(0.6)
              .frame(width: 14, height: 14)
          } else {
            Text(isEditing ? "Salvar" : "Criar")
          }
        }
        .buttonStyle(.plain)
        .foregroundColor(name.trimmingCharacters(in: .whitespaces).isEmpty ? Ink.secondary : .white)
        .padding(.horizontal, OmiSpacing.lg)
        .padding(.vertical, OmiSpacing.sm)
        .background(
          RoundedRectangle(cornerRadius: OmiChrome.elementRadius)
            .fill(
              name.trimmingCharacters(in: .whitespaces).isEmpty
                ? Ink.rowFillHover : Color(hex: selectedColor) ?? Ink.primary)
        )
        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
      }
      .padding(OmiSpacing.xl)
    }
    .onAppear {
      if let folder = folder {
        name = folder.name
        descriptionText = folder.description ?? ""
        selectedColor = folder.color
      }
    }
  }

  private func save() {
    let trimmedName = name.trimmingCharacters(in: .whitespaces)
    guard !trimmedName.isEmpty else { return }

    isSaving = true
    Task {
      if let folder = folder {
        await appState.updateFolder(
          folder.id,
          name: trimmedName,
          description: descriptionText.isEmpty ? nil : descriptionText,
          color: selectedColor
        )
      } else {
        _ = await appState.createFolder(
          name: trimmedName,
          description: descriptionText.isEmpty ? nil : descriptionText,
          color: selectedColor
        )
      }
      isSaving = false
      onDismiss()
    }
  }
}

// MARK: - Delete Folder Sheet

struct DeleteFolderSheet: View {
  let folder: Folder
  let onDismiss: () -> Void

  @EnvironmentObject var appState: AppState

  @State private var moveToFolderId: String? = nil
  @State private var isDeleting: Bool = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Header
      HStack {
        Text("Apagar pasta")
          .scaledFont(size: OmiType.subheading, weight: .semibold)
          .foregroundColor(Ink.primary)
        Spacer()
        DismissButton(action: onDismiss)
      }
      .padding(OmiSpacing.xl)

      Divider().background(Ink.rowFillHover)

      VStack(alignment: .leading, spacing: OmiSpacing.lg) {
        Text("Tem certeza de que quer apagar \"\(folder.name)\"?")
          .scaledFont(size: OmiType.body)
          .foregroundColor(Ink.primary)

        if folder.conversationCount > 0 {
          Text(
            "Esta pasta tem \(folder.conversationCount) \(folder.conversationCount == 1 ? "conversa" : "conversas"). Escolha para onde movê-las:"
          )
          .scaledFont(size: OmiType.body)
          .foregroundColor(Ink.secondary)

          // Move destination picker
          VStack(alignment: .leading, spacing: OmiSpacing.xxs) {
            moveOption(label: "Sem pasta (sem classificação)", folderId: nil)

            ForEach(appState.folders.filter { $0.id != folder.id }) { otherFolder in
              moveOption(label: otherFolder.name, folderId: otherFolder.id, color: otherFolder.color)
            }
          }
        }
      }
      .padding(OmiSpacing.xl)

      Divider().background(Ink.rowFillHover)

      // Action buttons
      HStack {
        Spacer()
        Button("Cancelar") {
          onDismiss()
        }
        .buttonStyle(.plain)
        .foregroundColor(Ink.secondary)
        .padding(.horizontal, OmiSpacing.lg)
        .padding(.vertical, OmiSpacing.sm)

        Button(action: performDelete) {
          if isDeleting {
            ProgressView()
              .scaleEffect(0.6)
              .frame(width: 14, height: 14)
          } else {
            Text("Apagar")
          }
        }
        .buttonStyle(.plain)
        .foregroundColor(Ink.surface)
        .padding(.horizontal, OmiSpacing.lg)
        .padding(.vertical, OmiSpacing.sm)
        .background(
          RoundedRectangle(cornerRadius: OmiChrome.elementRadius)
            .fill(Ink.errorRed)
        )
        .disabled(isDeleting)
      }
      .padding(OmiSpacing.xl)
    }
  }

  @ViewBuilder
  private func moveOption(label: String, folderId: String?, color: String? = nil) -> some View {
    let isSelected = moveToFolderId == folderId
    Button(action: {
      moveToFolderId = folderId
    }) {
      HStack(spacing: OmiSpacing.sm) {
        if let color = color, let c = Color(hex: color) {
          Circle()
            .fill(c)
            .frame(width: 8, height: 8)
        } else {
          Image(systemName: "tray")
            .scaledFont(size: OmiType.caption)
            .foregroundColor(Ink.secondary)
            .frame(width: 8)
        }
        Text(label)
          .scaledFont(size: OmiType.body)
          .foregroundColor(Ink.primary)
        Spacer()
        if isSelected {
          Image(systemName: "checkmark")
            .scaledFont(size: OmiType.caption, weight: .semibold)
            .foregroundColor(Ink.primary)
        }
      }
      .padding(.horizontal, OmiSpacing.sm)
      .padding(.vertical, OmiSpacing.sm)
      .background(
        RoundedRectangle(cornerRadius: OmiChrome.badgeRadius)
          .fill(isSelected ? Ink.rowFillHover : Color.clear)
      )
    }
    .buttonStyle(.plain)
  }

  private func performDelete() {
    isDeleting = true
    Task {
      await appState.deleteFolder(folder.id, moveToFolderId: moveToFolderId)
      isDeleting = false
      onDismiss()
    }
  }
}
