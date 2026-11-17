import OmiTheme
import SwiftUI

// MARK: - Search Data Model

struct SettingsSearchItem: Identifiable {
  let id = UUID()
  let name: String
  let subtitle: String
  let keywords: [String]
  let section: SettingsContentView.SettingsSection
  let icon: String
  let settingId: String

  var breadcrumb: String {
    section.displayTitle
  }

  static let allSearchableItems: [SettingsSearchItem] = [
    // General
    SettingsSearchItem(
      name: "Notificações", subtitle: "Status da permissão e dos banners do macOS",
      keywords: ["alerts", "notify", "banners", "system settings", "permission"], section: .general,
      icon: "gearshape",
      settingId: "general.notifications"),
    SettingsSearchItem(
      name: "Sons da Interface", subtitle: "Sons quando uma resposta termina ou um cartão aparece",
      keywords: ["sound", "sounds", "audio", "chime", "mute", "silence", "effects"],
      section: .general, icon: "speaker.wave.2", settingId: "general.interfacesounds"),
    SettingsSearchItem(
      name: "Tamanho da Fonte", subtitle: "Ajuste o tamanho do texto em todo o app",
      keywords: ["text size", "zoom", "scale", "reset"], section: .general, icon: "gearshape",
      settingId: "general.fontsize"),
    SettingsSearchItem(
      name: "Redefinir Tamanho da Janela", subtitle: "Restaura as dimensões padrão da janela",
      keywords: ["resize", "window", "default size"], section: .general, icon: "macwindow",
      settingId: "general.window"),
    SettingsSearchItem(
      name: "Transparência", subtitle: "Quão transparentes são as janelas do Omi",
      keywords: ["glass", "transparent", "opacity", "opaque", "blur", "see-through", "translucent"],
      section: .general, icon: "circle.lefthalf.filled", settingId: "general.transparency"),

    // Rewind
    SettingsSearchItem(
      name: "Rewind", subtitle: "Por quanto tempo o histórico de tela é mantido",
      keywords: ["screen history", "screenshots", "recording", "retention"], section: .rewind,
      icon: "clock.arrow.circlepath", settingId: "rewind.retention"),
    SettingsSearchItem(
      name: "Captura de Tela", subtitle: "Liga ou desliga a captura de tela",
      keywords: ["screen capture", "screenshot", "monitor", "recording", "rewind"],
      section: .general, icon: "rectangle.dashed.badge.record", settingId: "general.screencapture"),
    SettingsSearchItem(
      name: "Gravação de Áudio", subtitle: "Desligado, Sempre Ligado ou Só Reuniões",
      keywords: [
        "audio", "microphone", "recording", "transcription", "mic", "meeting", "zoom", "google meet",
        "teams", "call", "system audio",
      ], section: .general,
      icon: "mic.fill", settingId: "general.audiorecording"),
    SettingsSearchItem(
      name: "Armazenamento", subtitle: "Veja a contagem de quadros e o uso de disco",
      keywords: ["frames", "storage", "disk", "space", "gb"], section: .rewind,
      icon: "clock.arrow.circlepath", settingId: "rewind.storage"),
    SettingsSearchItem(
      name: "Apps Excluídos", subtitle: "A captura de tela é pausada quando estes apps estão ativos",
      keywords: ["exclude", "ignore", "block apps", "blocklist", "reset to defaults"],
      section: .rewind, icon: "clock.arrow.circlepath", settingId: "rewind.excludedapps"),
    SettingsSearchItem(
      name: "Otimização de Bateria", subtitle: "Economiza energia reduzindo a frequência das capturas",
      keywords: ["battery", "power", "energy", "low power"], section: .rewind,
      icon: "clock.arrow.circlepath", settingId: "rewind.battery"),
    SettingsSearchItem(
      name: "Retenção de Dados", subtitle: "Por quanto tempo manter as gravações de tela",
      keywords: ["retention", "storage", "delete old", "keep data"], section: .rewind,
      icon: "clock.arrow.circlepath", settingId: "rewind.retention"),
    SettingsSearchItem(
      name: "Capturas de Tela da Reunião", subtitle: "Adiciona às notas da reunião capturas do que estava na tela",
      keywords: ["meeting", "screenshots", "notes", "banner", "photos"], section: .rewind,
      icon: "photo.on.rectangle.angled", settingId: "rewind.meetingnotescreenshots"),

    // Transcription
    SettingsSearchItem(
      name: "Ajustes de Transcrição", subtitle: "Configure as opções de fala para texto",
      keywords: ["language", "vocabulary", "speech"], section: .transcription, icon: "waveform",
      settingId: "transcription.languagemode"),
    SettingsSearchItem(
      name: "Modo de Idioma", subtitle: "Escolha transcrição em um idioma ou em vários",
      keywords: ["language", "multilingual", "single language"], section: .transcription,
      icon: "waveform", settingId: "transcription.languagemode"),
    SettingsSearchItem(
      name: "Vocabulário Personalizado",
      subtitle: "Melhora o reconhecimento de nomes, marcas e termos técnicos",
      keywords: ["vocabulary", "words", "custom words", "dictionary"], section: .transcription,
      icon: "waveform", settingId: "transcription.vocabulary"),
    SettingsSearchItem(
      name: "Filtro VAD Local", subtitle: "Ignora o silêncio para reduzir o custo de transcrição",
      keywords: ["vad", "silence", "gate", "cost", "deepgram"], section: .transcription,
      icon: "waveform", settingId: "transcription.vadgate"),
    SettingsSearchItem(
      name: "Omi Type Silencioso", subtitle: "Mantém o que você dita com o Omi Type fora do chat",
      keywords: ["silent", "type", "dictation", "voice typing", "private", "chat context"],
      section: .transcription,
      icon: "keyboard", settingId: "transcription.silenttype"),
    SettingsSearchItem(
      name: "Ignorar Apps de Ditado",
      subtitle: "Para de escutar enquanto o Wispr Flow, o superwhisper ou o Ditado do macOS usa o microfone",
      keywords: ["dictation", "wispr", "superwhisper", "noise", "mute", "conversations"],
      section: .transcription,
      icon: "mic.slash", settingId: "transcription.ignoredictationapps"),

    // Notifications
    SettingsSearchItem(
      name: "Ajustes de Notificações", subtitle: "Controle com que frequência você recebe notificações",
      keywords: ["daily summary", "frequency", "alerts"], section: .notifications, icon: "bell",
      settingId: "notifications.settings"),
    SettingsSearchItem(
      name: "Frequência das Notificações", subtitle: "Quantas sugestões proativas o Omi envia",
      keywords: ["frequency", "how often", "interval"], section: .notifications, icon: "bell",
      settingId: "notifications.frequency"),
    SettingsSearchItem(
      name: "Notificações de Tarefas",
      subtitle: "Permite interrupções quando uma tarefa precisa de atenção",
      keywords: ["task", "action item", "notify task", "interruption", "proactive"],
      section: .notifications, icon: "bell",
      settingId: "notifications.task"),
    SettingsSearchItem(
      name: "Notificações de Memórias", subtitle: "Mostra uma notificação quando uma memória é extraída",
      keywords: ["memory", "facts", "notify memory"], section: .notifications, icon: "bell",
      settingId: "notifications.memory"),
    SettingsSearchItem(
      name: "Notificações de Integrações",
      subtitle: "De vez em quando oferece conectar um app que o Omi pode usar (Gmail, Notion, ChatGPT)",
      keywords: ["integration", "suggestions", "connect", "gmail", "notion", "nudge"],
      section: .notifications, icon: "bell",
      settingId: "notifications.integrationsuggestions"),
    SettingsSearchItem(
      name: "Conectar um Agente",
      subtitle: "Prompts de configuração e chaves de MCP e da API de Desenvolvedor para Claude, ChatGPT, Codex, Cursor",
      keywords: [
        "agent", "mcp", "api key", "developer", "claude", "chatgpt", "codex", "cursor", "openclaw",
        "hermes",
      ],
      section: .advanced, icon: "point.3.connected.trianglepath.dotted",
      settingId: "advanced.connectagent"),
    SettingsSearchItem(
      name: "Redefinir Sugestões de Integrações",
      subtitle: "Limpa o histórico de sugestões de todas as integrações para o Omi poder oferecê-las de novo",
      keywords: ["reset", "integration", "suggestions", "history", "again"],
      section: .advanced, icon: "wrench.and.screwdriver",
      settingId: "advanced.troubleshooting.resetintegrationsuggestions"),
    SettingsSearchItem(
      name: "Resumo do Dia",
      subtitle: "Receba um resumo diário das suas conversas e atividades",
      keywords: ["daily", "summary", "digest", "end of day"], section: .notifications, icon: "bell",
      settingId: "notifications.dailysummary"),
    SettingsSearchItem(
      name: "Horário do Resumo", subtitle: "Quando enviar seu resumo do dia (só a hora)",
      keywords: ["time", "schedule", "when", "hour"], section: .notifications, icon: "bell",
      settingId: "notifications.summarytime"),

    // Privacy
    SettingsSearchItem(
      name: "Privacidade", subtitle: "Controle seus dados e ajustes de privacidade",
      keywords: ["data", "encryption", "cloud sync", "recordings"], section: .privacy,
      icon: "lock.shield", settingId: "privacy.privacy"),
    SettingsSearchItem(
      name: "Armazenar Gravações",
      subtitle: "Permite que o Omi armazene gravações de áudio das suas conversas",
      keywords: ["store", "save recordings", "audio storage"], section: .privacy,
      icon: "lock.shield", settingId: "privacy.storerecordings"),
    SettingsSearchItem(
      name: "Sincronização em Nuvem Privada", subtitle: "Envie suas gravações para o seu próprio armazenamento na nuvem",
      keywords: ["cloud", "sync", "private cloud"], section: .privacy, icon: "lock.shield",
      settingId: "privacy.storerecordings"),
    SettingsSearchItem(
      name: "Criptografia", subtitle: "Criptografia no servidor para os seus dados",
      keywords: ["encrypt", "security", "end to end"], section: .privacy, icon: "lock.shield",
      settingId: "privacy.encryption"),
    SettingsSearchItem(
      name: "O Que Monitoramos", subtitle: "Veja os dados de uso que o Omi coleta",
      keywords: ["tracking", "analytics", "telemetry", "data collection"], section: .privacy,
      icon: "lock.shield", settingId: "privacy.tracking"),

    // Account
    SettingsSearchItem(
      name: "Conta", subtitle: "Seu perfil e e-mail", keywords: ["profile", "email"],
      section: .account, icon: "person.circle", settingId: "account.account"),
    SettingsSearchItem(
      name: "Sair", subtitle: "Saia da sua conta do Omi",
      keywords: ["sign out", "log out", "logout", "signout"], section: .account,
      icon: "person.circle", settingId: "account.signout"),

    // Plan and Usage
    SettingsSearchItem(
      name: "Plano e Uso", subtitle: "Status da assinatura e limites de uso",
      keywords: ["subscription", "billing", "plan", "usage", "stripe", "omi pro", "pro"],
      section: .planUsage, icon: "creditcard", settingId: "planusage.overview"),
    SettingsSearchItem(
      name: "Plano Atual", subtitle: "Veja sua assinatura atual e o status da renovação",
      keywords: ["current plan", "renewal", "billing"], section: .planUsage, icon: "creditcard",
      settingId: "planusage.current"),
    SettingsSearchItem(
      name: "Fazer Upgrade do Plano", subtitle: "Comprar o Omi Pro",
      keywords: ["upgrade", "buy", "pricing", "checkout", "omi pro", "pro"], section: .planUsage,
      icon: "creditcard", settingId: "planusage.purchase"),

    // Referral
    SettingsSearchItem(
      name: "Indique um Amigo", subtitle: "Compartilhe um mês grátis do Omi Pro",
      keywords: ["refer", "referral", "friend", "gift", "free month", "share link"],
      section: .referral, icon: "gift", settingId: "referral.link"),

    // About
    SettingsSearchItem(
      name: "Atualizações de Software", subtitle: "Verifique e gerencie as atualizações do app",
      keywords: ["update", "auto update", "sparkle", "version", "check for updates", "check now"],
      section: .about, icon: "info.circle", settingId: "about.updates"),
    SettingsSearchItem(
      name: "Atualizações Automáticas", subtitle: "Verifica atualizações automaticamente em segundo plano",
      keywords: ["auto check", "background updates", "check automatically"], section: .about,
      icon: "info.circle", settingId: "about.autoupdates"),
    SettingsSearchItem(
      name: "Instalar Atualizações Automaticamente",
      subtitle: "Baixa e instala atualizações automaticamente quando disponíveis",
      keywords: ["auto install", "automatic install", "download updates", "install updates"],
      section: .about, icon: "info.circle", settingId: "about.autoinstall"),
    SettingsSearchItem(
      name: "Omi Beta", subtitle: "Instale o app Omi Beta separado ao lado deste",
      keywords: ["channel", "beta", "stable", "release channel", "omi beta"], section: .about,
      icon: "info.circle", settingId: "about.channel"),
    SettingsSearchItem(
      name: "Informações da Versão", subtitle: "Versão atual do app e número da build",
      keywords: ["version", "build", "app version", "build number"], section: .about,
      icon: "info.circle", settingId: "about.version"),

    // Advanced subsections
    SettingsSearchItem(
      name: "Refazer Introdução", subtitle: "Reinicia o assistente de configuração só para esta versão do app",
      keywords: ["reset", "onboarding", "restart", "setup"], section: .advanced,
      icon: "arrow.counterclockwise", settingId: "advanced.resetonboarding"),
    SettingsSearchItem(
      name: "Perfil de Usuário da IA", subtitle: "Resumo gerado por IA das suas preferências e hábitos",
      keywords: ["profile", "generate", "generate now", "regenerate"], section: .advanced,
      icon: "brain", settingId: "advanced.aiuserprofile"),
    SettingsSearchItem(
      name: "Suas Estatísticas", subtitle: "Veja suas estatísticas de uso e atividade",
      keywords: ["statistics", "conversations", "usage"], section: .advanced, icon: "chart.bar",
      settingId: "advanced.stats"),
    SettingsSearchItem(
      name: "Modo Desenvolvedor", subtitle: "Ferramentas de desenvolvedor e opções de depuração",
      keywords: ["developer", "debug", "dev mode", "development"], section: .advanced, icon: "cpu",
      settingId: "aichat.devmode"),
    SettingsSearchItem(
      name: "Metas", subtitle: "Acompanhe metas pessoais com detecção de progresso por IA",
      keywords: ["goal", "target", "objective", "tracking"], section: .advanced, icon: "target",
      settingId: "advanced.goals"),
    SettingsSearchItem(
      name: "Gerar Metas Automaticamente",
      subtitle: "Sugere novas metas todo dia com base nas suas conversas e tarefas",
      keywords: ["auto generate", "suggest goals", "daily goals"], section: .advanced,
      icon: "target", settingId: "advanced.goals.autogenerate"),
    SettingsSearchItem(
      name: "Abrir ao Iniciar a Sessão", subtitle: "Abre o Omi automaticamente quando você inicia a sessão",
      keywords: ["startup", "login", "boot"], section: .advanced, icon: "slider.horizontal.3",
      settingId: "advanced.preferences.launchatlogin"),
    SettingsSearchItem(
      name: "Reportar um Problema", subtitle: "Salva neste Mac um relatório com dados ocultados para compartilhar manualmente",
      keywords: ["bug", "feedback", "logs", "report", "issue"], section: .advanced,
      icon: "wrench.and.screwdriver", settingId: "advanced.troubleshooting.reportissue"),
    SettingsSearchItem(
      name: "Reexaminar Arquivos", subtitle: "Reindexa seus arquivos e atualiza seu perfil de IA",
      keywords: ["index", "reindex", "rescan", "files", "scan", "file indexing", "profile"],
      section: .advanced, icon: "wrench.and.screwdriver",
      settingId: "advanced.troubleshooting.rescanfiles"),
  ]
}

enum SettingsSidebarMetrics {
  /// The settings sidebar is a **table of contents**, not a content column.
  ///
  /// It was 260 — the width of the app's *main* sidebar, which carries conversation titles and has
  /// something to do with the room. Nine section names do not, and that width spent the difference
  /// on whitespace to the right of "About" while the pane beside it is the thing anyone reads.
  ///
  /// The value is **derived from the longest label rather than chosen**, because this row truncates
  /// (`lineLimit(1)`, `.tail`) and a truncated item in a table of contents is worse than a wide one.
  /// The longest merged label is deliberately concise, so the table of contents
  /// can stay narrow without truncating or stealing room from the settings pane.
  static let expandedWidth: CGFloat = 208

  /// Headroom over the measured label requirement. See `expandedWidth`: a zero-slack fit truncated
  /// on a real build, so the fit is held open by this rather than by luck.
  static let labelSlack: CGFloat = 12
  static let horizontalInset: CGFloat = OmiSpacing.sm
  static let itemAvailableWidth = expandedWidth - 2 * horizontalInset
}

/// **The rows this list actually shows**, as a value rather than a literal inside a `body`.
///
/// `ShellDestination.unreachable()` reads it: `Permissions` is an established page whose only way in
/// is a row here, so "the row exists" has to be something a test can hold. Delete it and the
/// reachability check names the page that lost its door instead of leaving it to be discovered in
/// the app (INV-NAV-1).
enum SettingsSidebarRoutes {
  /// Merged nav: `.account` hosts Account & Plan (renders `.planUsage` content
  /// too) and `.notifications` hosts Notifications & Privacy (renders `.privacy`
  /// content too). The absorbed cases stay routable for deep links/automation
  /// and highlight their merged item via `sidebarItem`.
  ///
  /// Capture and account first, then the things you tune, with Permissions beside
  /// Notifications because both are access. Shortcuts / Advanced / About stay at the foot.
  static let visibleSections: [SettingsContentView.SettingsSection] = [
    .general,
    .account,
    .transcription,
    .rewind,
    .notifications,
    .permissions,
    .advanced,
    .referral,
    .about,
  ]
}

/// Settings sidebar that replaces the main sidebar when in settings
struct SettingsSidebar: View {
  @Binding var selectedSection: SettingsContentView.SettingsSection
  @Binding var highlightedSettingId: String?
  let onBack: () -> Void
  /// The page Back returns to ("‹ Tasks").
  var backTitle: String = "Chat"
  @ObservedObject var appState: AppState

  @State private var searchQuery = ""
  @FocusState private var isSearchFocused: Bool

  private let iconWidth: CGFloat = 20
  private let visibleSections = SettingsSidebarRoutes.visibleSections

  private var filteredSearchItems: [SettingsSearchItem] {
    guard !searchQuery.isEmpty else { return [] }
    let words = searchQuery.lowercased().split(separator: " ").map(String.init)
    guard !words.isEmpty else { return [] }
    return SettingsSearchItem.allSearchableItems.filter { item in
      let nameLower = item.name.lowercased()
      let subtitleLower = item.subtitle.lowercased()
      let keywordsLower = item.keywords.map { $0.lowercased() }
      return words.allSatisfy { word in
        nameLower.contains(word) || subtitleLower.contains(word)
          || keywordsLower.contains(where: { $0.contains(word) })
      }
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Back button header
      backButton
        .padding(.top, OmiSpacing.md)
        .padding(.horizontal, OmiSpacing.lg)

      Spacer().frame(height: OmiSpacing.xxl)

      // Settings title
      Text("Ajustes")
        .scaledFont(size: OmiType.heading, weight: .bold)
        .foregroundColor(Ink.primary)
        .padding(.horizontal, OmiSpacing.lg)
        .padding(.bottom, OmiSpacing.md)

      // Search field
      searchField
        .padding(.horizontal, OmiSpacing.md)
        .padding(.bottom, OmiSpacing.md)

      if searchQuery.isEmpty {
        // Normal settings sections
        ScrollView(showsIndicators: false) {
          VStack(alignment: .leading, spacing: OmiSpacing.hairline) {
            ForEach(visibleSections, id: \.self) { section in
              SettingsSidebarItem(
                section: section,
                isSelected: selectedSection.sidebarItem == section,
                iconWidth: iconWidth,
                showsMissingPermissionNotice: section == .permissions && appState.hasMissingPermissions,
                onTap: {
                  OmiMotion.withGated(.easeInOut(duration: 0.15)) {
                    selectedSection = section
                  }
                }
              )

            }
          }
        }
        .padding(.horizontal, OmiSpacing.sm)
      } else {
        // Search results
        searchResultsList
          .padding(.horizontal, OmiSpacing.sm)
      }

      Spacer()
    }
    .frame(width: SettingsSidebarMetrics.expandedWidth)
    // A half-step of shading, and deliberately not a second material: the host already wears the
    // glass (`PageGlassLane` in modern Settings, `LegacySidebarSurface` in old Home), and a
    // `.regularMaterial` here would be a within-window blur stacked on it.
    .background(Ink.rowFill)
  }

  private var searchField: some View {
    HStack(spacing: OmiSpacing.sm) {
      Image(systemName: "magnifyingglass")
        .scaledFont(size: OmiType.body)
        .foregroundColor(isSearchFocused ? Ink.accent : Ink.secondary)
        .omiAnimation(.easeInOut(duration: 0.15), value: isSearchFocused)

      TextField("Buscar", text: $searchQuery)
        .textFieldStyle(.plain)
        .scaledFont(size: OmiType.body)
        .foregroundColor(Ink.primary)
        .focused($isSearchFocused)
        .straysTypingHere($isSearchFocused)
        .focusesOnFind($isSearchFocused)

      if !searchQuery.isEmpty {
        ClearFieldButton { searchQuery = "" }
      }
    }
    .padding(.horizontal, OmiSpacing.sm)
    .padding(.vertical, OmiSpacing.sm)
    .background(
      RoundedRectangle(cornerRadius: SettingsGlassMetrics.controlRadius, style: .continuous)
        .fill(Ink.wash)
        .overlay(
          RoundedRectangle(cornerRadius: SettingsGlassMetrics.controlRadius, style: .continuous)
            // Focused takes the one accent at full strength; at rest it is a control outline, which
            // is `Ink.hairline` and not `Ink.separator` — a field is something you type into.
            .strokeBorder(isSearchFocused ? Ink.accent : Ink.hairline, lineWidth: 1)
        )
    )
  }

  private var searchResultsList: some View {
    ScrollView(showsIndicators: false) {
      VStack(alignment: .leading, spacing: OmiSpacing.hairline) {
        if filteredSearchItems.isEmpty {
          Text("Nenhum resultado")
            .scaledFont(size: OmiType.body)
            .foregroundColor(Ink.secondary)
            .padding(.horizontal, OmiSpacing.md)
            .padding(.vertical, OmiSpacing.xl)
        } else {
          ForEach(filteredSearchItems) { item in
            SettingsSearchResultRow(item: item) {
              OmiMotion.withGated(.easeInOut(duration: 0.15)) {
                selectedSection = item.section
              }
              searchQuery = ""
              let targetId = item.settingId
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                highlightedSettingId = targetId
              }
            }
          }
        }
      }
    }
  }

  private var backButton: some View {
    BackChip(backTitle, accessibilityIdentifier: "settings-back", action: onBack)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

// MARK: - Settings Sidebar Item
struct SettingsSidebarItem: View {
  let section: SettingsContentView.SettingsSection
  let isSelected: Bool
  let iconWidth: CGFloat
  var showsMissingPermissionNotice: Bool = false
  let onTap: () -> Void

  @State private var isHovered = false

  private var icon: String {
    switch section {
    case .general: return "gearshape"
    case .rewind: return "clock.arrow.circlepath"
    case .transcription: return "waveform"
    case .notifications: return "bell"
    case .privacy: return "lock.shield"
    case .account: return "person.circle"
    case .planUsage: return "creditcard"
    case .advanced: return "cpu"
    case .referral: return "gift"
    case .about: return "info.circle"
    case .permissions: return PermissionNavSymbol.outline
    }
  }

  var body: some View {
    Button(action: onTap) {
      // The settings kit's row metrics rather than generic spacing tokens, so a row in the
      // table of contents and a row in the pane beside it are the same object at the same
      // rhythm — and so the narrower sidebar keeps the longest label off its own edge.
      HStack(spacing: SettingsGlassMetrics.rowContentSpacing) {
        Image(systemName: icon)
          .scaledFont(size: OmiType.subheading)
          .foregroundColor(SettingsSelection.rowIcon(isSelected: isSelected))
          .frame(width: iconWidth)

        Text(section.displayTitle)
          .scaledFont(size: OmiType.body, weight: SettingsSelection.rowWeight(isSelected: isSelected))
          .foregroundColor(Ink.primary)
          .lineLimit(1)
          .truncationMode(.tail)
          .layoutPriority(1)

        if showsMissingPermissionNotice {
          Image(systemName: PermissionNavSymbol.missingNotice)
            .scaledFont(size: OmiType.caption, weight: .semibold)
            .foregroundColor(SettingsInk.notice)
            .accessibilityHidden(true)
        }

        Spacer(minLength: 0)
      }
      .padding(.horizontal, SettingsGlassMetrics.rowHorizontalPadding)
      .padding(.vertical, SettingsGlassMetrics.rowVerticalPadding)
      .contentShape(Rectangle())
      .background(
        // The top bar's pill ladder, so the current page is marked the way the current tab is.
        // See `SettingsSelection`.
        RoundedRectangle(cornerRadius: SettingsGlassMetrics.controlRadius, style: .continuous)
          .fill(SettingsSelection.rowFill(isSelected: isSelected, isHovering: isHovered))
      )
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      isHovered = hovering
    }
    .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    .accessibilityLabel(
      Text(
        showsMissingPermissionNotice
          ? "\(section.displayTitle), permissões necessárias"
          : section.displayTitle)
    )
  }
}

// MARK: - Settings Subsection Item
struct SettingsSubsectionItem: View {
  let subsection: SettingsContentView.AdvancedSubsection
  let isSelected: Bool
  let iconWidth: CGFloat
  let onTap: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: onTap) {
      HStack(spacing: OmiSpacing.sm) {
        // Indentation spacer
        Spacer()
          .frame(width: iconWidth + 12)

        Image(systemName: subsection.icon)
          .scaledFont(size: OmiType.body)
          .foregroundColor(SettingsSelection.rowIcon(isSelected: isSelected))
          .frame(width: 16)

        Text(subsection.displayTitle)
          .scaledFont(size: OmiType.body, weight: SettingsSelection.rowWeight(isSelected: isSelected))
          .foregroundColor(Ink.primary)

        Spacer()
      }
      .padding(.horizontal, OmiSpacing.md)
      .padding(.vertical, OmiSpacing.sm)
      .contentShape(Rectangle())
      .background(
        RoundedRectangle(cornerRadius: SettingsGlassMetrics.controlRadius, style: .continuous)
          .fill(SettingsSelection.rowFill(isSelected: isSelected, isHovering: isHovered))
      )
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      isHovered = hovering
    }
    .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
  }
}

// MARK: - Settings Search Result Row
struct SettingsSearchResultRow: View {
  let item: SettingsSearchItem
  let onTap: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: onTap) {
      HStack(spacing: OmiSpacing.sm) {
        Image(systemName: item.icon)
          .scaledFont(size: OmiType.body)
          .foregroundColor(Ink.secondary)
          .frame(width: 20)

        VStack(alignment: .leading, spacing: OmiSpacing.hairline) {
          Text(item.name)
            .scaledFont(size: OmiType.body, weight: .medium)
            .foregroundColor(Ink.primary)

          Text(item.breadcrumb)
            .scaledFont(size: OmiType.caption)
            .foregroundColor(Ink.secondary)
        }

        Spacer()
      }
      .padding(.horizontal, OmiSpacing.md)
      .padding(.vertical, OmiSpacing.sm)
      .contentShape(Rectangle())
      .background(
        RoundedRectangle(cornerRadius: SettingsGlassMetrics.controlRadius, style: .continuous)
          .fill(isHovered ? Ink.rowHover : Color.clear)
      )
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      isHovered = hovering
    }
  }
}

// MARK: - Setting Highlight Modifier

struct SettingHighlightModifier: ViewModifier {
  let settingId: String
  @Binding var highlightedSettingId: String?
  @State private var isHighlighted = false

  func body(content: Content) -> some View {
    content
      .id(settingId)
      .overlay(
        // The "here it is" flash after a search jump: a wash of the one accent plus its edge, cut to
        // the card's own corner so the flash lands on the card rather than beside it.
        RoundedRectangle(cornerRadius: SettingsGlassMetrics.cardRadius, style: .continuous)
          .fill(isHighlighted ? Ink.accent.opacity(0.12) : Color.clear)
          .overlay(
            RoundedRectangle(cornerRadius: SettingsGlassMetrics.cardRadius, style: .continuous)
              .strokeBorder(isHighlighted ? Ink.accent : Color.clear, lineWidth: 1)
          )
          .omiAnimation(.easeInOut(duration: 0.3), value: isHighlighted)
          .allowsHitTesting(false)
      )
      .onChange(of: highlightedSettingId) { _, newId in
        if newId == settingId {
          OmiMotion.withGated { isHighlighted = true }
          DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            OmiMotion.withGated(.easeInOut(duration: 0.5)) { isHighlighted = false }
            if highlightedSettingId == settingId { highlightedSettingId = nil }
          }
        }
      }
  }
}

#if canImport(PreviewsMacros)
  #Preview {
    SettingsSidebar(
      selectedSection: .constant(.advanced),
      highlightedSettingId: .constant(nil),
      onBack: {},
      appState: AppState()
    )
    .preferredColorScheme(.light)
  }
#endif
