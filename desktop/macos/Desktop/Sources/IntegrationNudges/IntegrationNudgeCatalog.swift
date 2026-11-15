import Foundation

/// Where a nudge sends the user when they accept it.
///
/// Both cases already exist as automation presentation targets, so accepting a
/// nudge opens exactly the sheet the Apps tab would — there is no second,
/// nudge-only connect path that could drift from the real one.
enum IntegrationNudgeRoute: Equatable, Hashable {
  /// An `ImportConnector.id` — data flowing *into* Omi.
  case importConnector(String)
  /// A `MemoryExportDestination.rawValue` — Omi's memory flowing *out* to a tool.
  case exportDestination(String)

  /// The connector/destination identifier, as the sheet APIs expect it.
  var identifier: String {
    switch self {
    case .importConnector(let id), .exportDestination(let id): return id
    }
  }

  /// Which half of the catalog this is, as a bounded telemetry value.
  var telemetryPrefix: String {
    switch self {
    case .importConnector: return "import"
    case .exportDestination: return "export"
    }
  }

  /// A globally unique, bounded telemetry value. ChatGPT and Claude exist on
  /// both sides of the catalog, so the bare identifier would collide.
  var telemetryID: String {
    switch self {
    case .importConnector(let id): return "import:\(id)"
    case .exportDestination(let id): return "export:\(id)"
    }
  }
}

/// How an integration is recognized from the frontmost window.
enum IntegrationNudgeTriggerMatch: Equatable {
  /// The frontmost application is one of these bundle identifiers.
  case application(bundleIdentifiers: [String])
  /// The frontmost application is a browser and its window *title* ends with the
  /// site's own name, case-insensitively.
  ///
  /// A window title is the page's `document.title`, never its URL, so a domain
  /// keyword matches nothing real. What is reliable is where sites put their own
  /// name: at the end, behind a separator. X renders "Home / X", Gmail "Inbox
  /// (12) - you@corp.com - Gmail", ChatGPT just "ChatGPT".
  ///
  /// The name must be the *whole* title or sit behind a separator — a bare
  /// "ends with" test reads any sentence that happens to trail off in the name
  /// as the site itself. Measured against 95,577 real titles from this
  /// developer's own browser history, the unanchored form claimed "How to Create
  /// Studio Ghibli Style Art With ChatGPT" as ChatGPT, "Context for Claude" as
  /// Claude, and "World Wealth Report 2024: HNWI Wealth Management | Capgemini"
  /// as Gemini. Requiring the separator drops all three and costs no real title.
  ///
  /// An integration whose real titles carry no site name gets no browser trigger
  /// at all rather than a guess. Notion web titles are the page name alone, and
  /// Google Calendar leads with its name ("Google Calendar - Week of…") exactly
  /// as an article about it would, so both rely on their desktop apps.
  ///
  /// Title matching rather than URL reading is deliberate: the title comes from
  /// the same active-window lookup the proactive assistants already use, and
  /// reading the address bar would mean driving the Accessibility API across
  /// every browser.
  case browserTitleSite(names: [String])
  /// The frontmost application is a browser showing a Gmail mailbox whose
  /// account is on a Google Workspace domain.
  ///
  /// Workspace replaces "Gmail" in the title with the organization's own name —
  /// "Inbox (3,012) - you@company.com - Acme Mail" — so `browserTitleSite` can
  /// never name it. That is not an edge case: in the same 95,577-title corpus it
  /// is 51% of all Gmail visits, and every one of them was invisible to the
  /// nudge. The shape that identifies it is the account address Gmail puts in
  /// the middle segment; " Mail" alone would claim Proton and Yahoo too.
  case browserTitleGoogleWorkspaceMailbox
}

struct IntegrationNudgeTrigger: Equatable {
  /// Bounded telemetry value naming *what was recognized*. Never the raw app
  /// name or window title.
  let id: String
  let match: IntegrationNudgeTriggerMatch

  var kind: IntegrationNudgeTelemetry.TriggerKind {
    switch match {
    case .application: return .nativeApp
    case .browserTitleSite, .browserTitleGoogleWorkspaceMailbox: return .browserSite
    }
  }
}

/// One integration, its pitch, and what recognizes it.
///
/// This is the single source of truth for integration value propositions. The
/// proactive nudge and the connector sheet's "What you get" section read the
/// same `pitch`/`useCases`/`dataScope`, so a user who is nudged and a user who
/// browses the Apps tab are told the same thing.
struct IntegrationNudgeCatalogEntry: Equatable {
  let route: IntegrationNudgeRoute
  /// Human display name. Matches the cross-platform `integration_name`
  /// telemetry dimension where one already exists.
  let displayName: String
  let brand: ConnectorBrand
  /// One sentence, concrete, second person. This is the notification body.
  let pitch: String
  /// Three specific things the user can do once connected. Vague benefits
  /// ("better context") are worse than nothing — each of these names a thing
  /// the user could not do a minute ago.
  let useCases: [String]
  /// Plainly what Omi reads or is given. A nudge that asks for access without
  /// saying what it touches is a dark pattern, so this is not optional.
  let dataScope: String
  /// Empty for integrations that have no reliable foreground signal. Those
  /// entries still supply onboarding copy; they simply never nudge.
  let triggers: [IntegrationNudgeTrigger]

  var connectorID: String { route.identifier }
  var telemetryID: String { route.telemetryID }
  var canNudge: Bool { !triggers.isEmpty }
}

enum IntegrationNudgeCatalog {
  /// Browsers whose window title is treated as a site signal. A browser not on
  /// this list simply never produces a site trigger — the failure mode is a
  /// missed nudge, never a wrong one.
  static let browserBundleIdentifiers: Set<String> = [
    "com.apple.Safari",
    "com.apple.SafariTechnologyPreview",
    "com.google.Chrome",
    "com.google.Chrome.beta",
    "com.google.Chrome.canary",
    "com.microsoft.edgemac",
    "com.microsoft.edgemac.Beta",
    "com.microsoft.edgemac.Dev",
    "com.microsoft.edgemac.Canary",
    "com.brave.Browser",
    "com.brave.Browser.beta",
    "com.brave.Browser.nightly",
    "org.mozilla.firefox",
    "org.mozilla.firefoxdeveloperedition",
    "company.thebrowser.Browser",
    "company.thebrowser.dia",
    "com.vivaldi.Vivaldi",
    "com.operasoftware.Opera",
    "com.operasoftware.OperaGX",
    "com.openai.atlas",
    "com.kagi.kagimacOS",
    "app.zen-browser.zen",
    "ai.perplexity.comet",
  ]

  static let all: [IntegrationNudgeCatalogEntry] = [
    // MARK: Imports — data flowing into Omi

    IntegrationNudgeCatalogEntry(
      route: .importConnector("calendar"),
      displayName: "Google Calendar",
      brand: .calendar,
      pitch: "O Omi vê suas reuniões antes de acontecerem e lembra do que saiu delas.",
      useCases: [
        "Entre numa chamada já sabendo com quem vai falar e o que discutiram da última vez.",
        "Pergunte \"o que combinei na daily de segunda?\" e receba a resposta com a reunião anexada.",
        "O Omi enxerga suas reuniões reais e se organiza em torno delas.",
      ],
      dataScope: "Lê títulos, horários e participantes dos eventos da sua agenda.",
      triggers: [
        IntegrationNudgeTrigger(
          id: "calendar_app",
          match: .application(bundleIdentifiers: [
            "com.apple.iCal",
            "com.flexibits.fantastical2.mac",
            "com.cron.electron",
          ])
        )
      ]
    ),

    IntegrationNudgeCatalogEntry(
      route: .importConnector("email"),
      displayName: "Gmail",
      brand: .gmail,
      pitch: "O Omi pode ler sua caixa de entrada e saber o que você deve às pessoas e o que elas devem a você.",
      useCases: [
        "Pergunte \"o que estou esperando da Sarah?\" e receba a conversa, não uma caixa de busca.",
        "Traga à tona acompanhamentos que você prometeu num e-mail e nunca anotou em outro lugar.",
        "Dê ao Omi o histórico por trás de um nome para que uma nova conversa não comece do zero.",
      ],
      dataScope: "Lê suas mensagens do Gmail. O Omi nunca envia e-mails em seu nome.",
      triggers: [
        IntegrationNudgeTrigger(
          id: "gmail_web",
          match: .browserTitleSite(names: ["Gmail"])
        ),
        IntegrationNudgeTrigger(
          id: "gmail_workspace_web",
          match: .browserTitleGoogleWorkspaceMailbox
        ),
        IntegrationNudgeTrigger(
          id: "gmail_client_app",
          match: .application(bundleIdentifiers: ["com.mimestream.Mimestream"])
        ),
      ]
    ),

    IntegrationNudgeCatalogEntry(
      route: .importConnector("local-files"),
      displayName: "Arquivos locais",
      brand: .localFiles,
      pitch: "O Omi pode indexar os documentos e o código em que você realmente trabalha, sem que nada saia do seu Mac.",
      useCases: [
        "Encontre uma especificação ou um contrato pelo que ele dizia, não pelo lugar onde você o guardou.",
        "Receba respostas que citam seus próprios arquivos em vez de adivinhar.",
        "Mantenha todo o índice no dispositivo: nada é enviado.",
      ],
      dataScope: "Indexa as pastas que você escolher, no dispositivo.",
      triggers: [
        IntegrationNudgeTrigger(
          id: "finder",
          match: .application(bundleIdentifiers: ["com.apple.finder"])
        )
      ]
    ),

    IntegrationNudgeCatalogEntry(
      route: .importConnector("apple-notes"),
      displayName: "Apple Notes",
      brand: .appleNotes,
      pitch: "O Omi pode buscar nas suas notas do Apple Notes.",
      useCases: [
        "Encontre uma nota descrevendo-a, mesmo sem as palavras exatas.",
        "Deixe o Omi ligar algo que você escreveu em março à conversa que você está tendo hoje.",
        "Pare de explicar de novo um contexto que você já registrou uma vez.",
      ],
      dataScope: "Lê o texto das suas notas locais do Apple Notes.",
      triggers: [
        IntegrationNudgeTrigger(
          id: "apple_notes_app",
          match: .application(bundleIdentifiers: ["com.apple.Notes"])
        )
      ]
    ),

    IntegrationNudgeCatalogEntry(
      route: .importConnector("x"),
      displayName: "X",
      brand: .x,
      pitch: "O Omi pode aprender com o que você posta, salva e curte no X.",
      useCases: [
        "Pergunte \"qual era aquele thread que salvei sobre preços?\" e receba de volta.",
        "Transforme um ano de itens salvos em algo em que você consegue buscar.",
        "Deixe o Omi usar o que você já disse publicamente como contexto de como você pensa.",
      ],
      dataScope: "Lê seus próprios posts, itens salvos e curtidas.",
      triggers: [
        IntegrationNudgeTrigger(
          id: "x_web",
          match: .browserTitleSite(names: ["X", "Twitter"])
        )
      ]
    ),

    // The two memory-log imports carry no triggers: opening ChatGPT is a much
    // better moment to offer the MCP connector below (which makes ChatGPT
    // smarter about you) than to ask the user to go export a memory file. They
    // exist here so the Apps-tab sheet has the same onboarding copy as
    // everything else.
    IntegrationNudgeCatalogEntry(
      route: .importConnector("chatgpt"),
      displayName: "ChatGPT",
      brand: .chatgpt,
      pitch: "Traga para o Omi o que o ChatGPT já sabe sobre você.",
      useCases: [
        "Comece o Omi com as preferências e o histórico que você passou um ano ensinando ao ChatGPT.",
        "Mantenha uma só memória em vez de dividi-la entre dois apps.",
        "Importe uma vez. Depois disso, o Omi adiciona novas memórias das suas conversas.",
      ],
      dataScope: "Você cola uma exportação de memória do ChatGPT. O Omi nunca entra na sua conta do ChatGPT.",
      triggers: []
    ),

    IntegrationNudgeCatalogEntry(
      route: .importConnector("claude"),
      displayName: "Claude",
      brand: .claude,
      pitch: "Traga para o Omi o que o Claude já sabe sobre você.",
      useCases: [
        "Comece o Omi com o contexto que você já construiu no Claude.",
        "Mantenha uma só memória em vez de dividi-la entre dois apps.",
        "Importe uma vez. Depois disso, o Omi adiciona novas memórias das suas conversas.",
      ],
      dataScope: "Você cola uma exportação de memória do Claude. O Omi nunca entra na sua conta do Claude.",
      triggers: []
    ),

    // MARK: Exports — Omi's memory flowing out to a tool

    IntegrationNudgeCatalogEntry(
      route: .exportDestination("chatgpt"),
      displayName: "ChatGPT",
      brand: .chatgpt,
      pitch: "Dê ao ChatGPT tudo o que o Omi lembra sobre você.",
      useCases: [
        "Abra uma nova conversa no ChatGPT que já conhece seus projetos e suas pessoas.",
        "Pare de colar o mesmo parágrafo de contexto em todo chat.",
        "Pergunte ao ChatGPT sobre algo que você disse em voz alta na semana passada.",
      ],
      dataScope: "Permite que o ChatGPT consulte suas memórias e conversas do Omi. Revogável a qualquer momento.",
      triggers: [
        IntegrationNudgeTrigger(
          id: "chatgpt_app",
          match: .application(bundleIdentifiers: ["com.openai.chat"])
        ),
        IntegrationNudgeTrigger(
          id: "chatgpt_web",
          match: .browserTitleSite(names: ["ChatGPT"])
        ),
      ]
    ),

    IntegrationNudgeCatalogEntry(
      route: .exportDestination("claude"),
      displayName: "Claude",
      brand: .claude,
      pitch: "Dê ao Claude tudo o que o Omi lembra sobre você.",
      useCases: [
        "Comece uma conversa no Claude que já tem seu contexto carregado.",
        "Peça ao Claude para redigir algo no seu estilo, a partir do seu próprio histórico.",
        "Pule o novo briefing no início de cada chat.",
      ],
      dataScope: "Permite que o Claude consulte suas memórias e conversas do Omi. Revogável a qualquer momento.",
      triggers: [
        IntegrationNudgeTrigger(
          id: "claude_app",
          match: .application(bundleIdentifiers: ["com.anthropic.claudefordesktop"])
        ),
        IntegrationNudgeTrigger(
          id: "claude_web",
          match: .browserTitleSite(names: ["Claude"])
        ),
      ]
    ),

    IntegrationNudgeCatalogEntry(
      route: .exportDestination("gemini"),
      displayName: "Gemini",
      brand: .gemini,
      pitch: "Dê ao Gemini tudo o que o Omi lembra sobre você.",
      useCases: [
        "Pergunte ao Gemini sobre a sua semana, não só sobre a internet pública.",
        "Leve seu contexto do Omi para as ferramentas do Google sem copiar e colar.",
        "Mantenha uma só memória entre os assistentes que você realmente usa.",
      ],
      dataScope: "Permite que o Gemini consulte suas memórias e conversas do Omi. Revogável a qualquer momento.",
      triggers: [
        IntegrationNudgeTrigger(
          id: "gemini_web",
          match: .browserTitleSite(names: ["Google Gemini", "Gemini"])
        )
      ]
    ),

    IntegrationNudgeCatalogEntry(
      route: .exportDestination("notion"),
      displayName: "Notion",
      brand: .notion,
      pitch: "O Omi pode escrever o que aprende no workspace do Notion que você já mantém.",
      useCases: [
        "Leve notas e conclusões de reuniões para onde sua equipe já procura.",
        "Pare de redigitar num documento as decisões de uma conversa.",
        "Mantenha um workspace como registro em vez de dois registros pela metade.",
      ],
      dataScope: "Grava memórias do Omi no workspace do Notion que você autorizar.",
      triggers: [
        IntegrationNudgeTrigger(
          id: "notion_app",
          match: .application(bundleIdentifiers: ["notion.id"])
        )
      ]
    ),

    IntegrationNudgeCatalogEntry(
      route: .exportDestination("obsidian"),
      displayName: "Obsidian",
      brand: .obsidian,
      pitch: "O Omi pode colocar o que aprende direto no seu cofre do Obsidian.",
      useCases: [
        "Receba conversas e memórias como notas no cofre a partir do qual você já faz links.",
        "Mantenha tudo local e em texto simples, como o cofre já é.",
        "Deixe suas notas diárias se preencherem sozinhas com o que você realmente fez.",
      ],
      dataScope: "Grava memórias do Omi na pasta do cofre que você escolher, no dispositivo.",
      triggers: [
        IntegrationNudgeTrigger(
          id: "obsidian_app",
          match: .application(bundleIdentifiers: ["md.obsidian"])
        )
      ]
    ),

    // Entries below have no reliable foreground signal: a terminal window is
    // not evidence that Claude Code or Codex is running in it, and the agent
    // runtimes have no window of their own. They carry onboarding copy for the
    // connector sheet and never nudge.

    IntegrationNudgeCatalogEntry(
      route: .exportDestination("claudeCode"),
      displayName: "Claude Code",
      brand: .claudeCode,
      pitch: "Dê ao Claude Code sua memória do Omi, para ele programar com o seu contexto.",
      useCases: [
        "Deixe o agente ler decisões que você tomou em voz alta, não só o que está no repositório.",
        "Pule a explicação do mesmo contexto do projeto no início de cada sessão.",
        "Mantenha uma só memória entre seu editor e seu assistente.",
      ],
      dataScope: "Adiciona o Omi como servidor MCP na configuração do Claude Code.",
      triggers: []
    ),

    IntegrationNudgeCatalogEntry(
      route: .exportDestination("codex"),
      displayName: "Codex",
      brand: .codex,
      pitch: "Dê ao Codex sua memória do Omi, para ele programar com o seu contexto.",
      useCases: [
        "Deixe o agente ler decisões que você tomou em voz alta, não só o que está no repositório.",
        "Pule a descrição do projeto no início de cada sessão.",
        "Mantenha uma só memória entre seu editor e seu assistente.",
      ],
      dataScope: "Adiciona o Omi como servidor MCP na configuração do Codex.",
      triggers: []
    ),

    IntegrationNudgeCatalogEntry(
      route: .exportDestination("openclaw"),
      displayName: "OpenClaw",
      brand: .openclaw,
      pitch: "Dê ao OpenClaw sua memória do Omi, para os agentes dele trabalharem com o seu contexto.",
      useCases: [
        "Os agentes dele começam com o que o Omi já sabe sobre você.",
        "Passe trabalho adiante sem precisar escrever um briefing antes.",
        "Mantenha uma só memória entre todos os agentes que você usa.",
      ],
      dataScope: "Adiciona o Omi como servidor MCP na configuração do OpenClaw.",
      triggers: []
    ),

    IntegrationNudgeCatalogEntry(
      route: .exportDestination("hermes"),
      displayName: "Hermes",
      brand: .hermes,
      pitch: "Dê ao Hermes sua memória do Omi, para os agentes dele trabalharem com o seu contexto.",
      useCases: [
        "Os agentes dele começam com o que o Omi já sabe sobre você.",
        "Passe trabalho adiante sem precisar escrever um briefing antes.",
        "Mantenha uma só memória entre todos os agentes que você usa.",
      ],
      dataScope: "Adiciona o Omi como servidor MCP na configuração do Hermes.",
      triggers: []
    ),

    IntegrationNudgeCatalogEntry(
      route: .exportDestination("agents"),
      displayName: "Agentes",
      brand: .agents,
      pitch: "Dê aos seus próprios agentes a mesma memória que o Omi tem.",
      useCases: [
        "Conecte qualquer agente compatível com MCP à sua memória do Omi.",
        "Os agentes partem do seu histórico em vez de começar do zero.",
        "Revogue o acesso em um só lugar quando terminar.",
      ],
      dataScope: "Expõe sua memória do Omi via MCP ao agente que você autorizar.",
      triggers: []
    ),
  ]

  /// Entries that can actually fire a nudge.
  static var nudgeable: [IntegrationNudgeCatalogEntry] { all.filter(\.canNudge) }

  static func entry(for route: IntegrationNudgeRoute) -> IntegrationNudgeCatalogEntry? {
    all.first { $0.route == route }
  }

  /// Resolve an entry from the value carried on a notification action.
  static func entry(telemetryID: String) -> IntegrationNudgeCatalogEntry? {
    all.first { $0.telemetryID == telemetryID }
  }

  /// Onboarding copy for an Apps-tab import connector. Returns nil for ids the
  /// catalog has no entry for, so a new connector shows its existing one-line
  /// description rather than nothing.
  static func importEntry(connectorID: String) -> IntegrationNudgeCatalogEntry? {
    entry(for: .importConnector(connectorID))
  }

  static func exportEntry(destinationID: String) -> IntegrationNudgeCatalogEntry? {
    entry(for: .exportDestination(destinationID))
  }

  /// Every telemetry id in the catalog, used by the store's reset path.
  static var allTelemetryIDs: [String] { all.map(\.telemetryID) }
}
