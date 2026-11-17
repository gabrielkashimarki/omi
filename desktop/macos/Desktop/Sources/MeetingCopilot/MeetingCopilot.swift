import AppKit
import Combine
import WebKit

/// Copiloto de reunião: painel flutuante com o `meeting.html` do Atticus (MIT, Copyright (c) 2026 SaarthurR),
/// embutido em `Contents/Resources/atticus/ui` pelo `scripts/embutir-atticus.sh`.
/// Abre e fecha com a reunião confirmada pelo `MeetingDetector`, mostra a transcrição do Omi e responde
/// às perguntas dos outros com o Gemini (filtro do Atticus em `MeetingCopilotPrompt`).
/// A página fala com o Swift por mensagens `{do: ...}` e o Swift chama `window.meeting.*`.
@MainActor
final class MeetingCopilot: NSObject, WKScriptMessageHandler {
  static let shared = MeetingCopilot()
  private static let enabledKey = "meetingCopilotEnabled"
  // ponytail: modelo fixo; vira ajuste quando o flash não bastar
  private static let answerModel = "gemini-3.8-flash"

  private var panel: CopilotPanel?
  private var web: WKWebView?
  private var loaded = false
  private var running = false
  private var minimized = false
  private var voicing = false
  private var expanded = NSSize(width: 340, height: 650)
  private var began = Date()
  private var serial = 0
  private var clock: Timer?
  private var subscriptions: Set<AnyCancellable> = []

  // Transcrição do Omi já mandada para a página
  private var sentLines: [String: Bool] = [:]  // id do segmento -> já virou linha final
  private var transcript: [MeetingCopilotPrompt.Line] = []
  private var askedSegments: Set<String> = []
  private var settle: DispatchWorkItem?

  // Reunião da extensão no servidor: enquanto houver, a transcrição com nomes vem de lá
  private var server: MeetingCopilotServer.Meeting?
  private var serverAfter: Int?
  private var serverPoll: Task<Void, Never>?

  // Contexto e o que fica salvo na conversa do Omi
  private var notes = ""
  private var memoryBrief = ""
  private var savedNoteId: Int64?
  private var answers: [(question: String, lines: [String])] = []

  private var mouseDown: NSPoint?
  private var dragOrigin: NSRect?
  private var dragMonitor: Any?

  private var enabled: Bool {
    UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
  }

  /// Sinal confirmado do `MeetingDetector`.
  func meetingChanged(_ active: Bool) {
    if active {
      guard enabled, panel == nil else { return }
      open()
    } else if running {
      stop(paused: false)
    }
  }

  // MARK: - Painel

  private func open() {
    guard let dir = Bundle.main.resourceURL?.appendingPathComponent("atticus/ui"),
      let html = try? String(contentsOf: dir.appendingPathComponent("meeting.html"), encoding: .utf8)
    else {
      log("MeetingCopilot: meeting.html não está no app; rode scripts/embutir-atticus.sh")
      return
    }
    let orbs = (try? String(contentsOf: dir.appendingPathComponent("orbs.js"), encoding: .utf8)) ?? ""
    let i18n = (try? String(contentsOf: dir.appendingPathComponent("i18n.js"), encoding: .utf8)) ?? ""

    resetSession()
    let screen = NSScreen.main ?? NSScreen.screens[0]
    let visible = screen.visibleFrame
    let frame = NSRect(
      x: visible.maxX - expanded.width - 12, y: visible.maxY - expanded.height - 12,
      width: expanded.width, height: expanded.height)
    let p = CopilotPanel(
      contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    p.level = .statusBar
    p.isOpaque = false
    p.backgroundColor = .clear
    p.hasShadow = true
    p.hidesOnDeactivate = false
    p.acceptsMouseMovedEvents = true
    p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    p.sharingType = .none  // não aparece no compartilhamento de tela nem na captura do "explicar a tela"

    let config = WKWebViewConfiguration()
    config.userContentController.add(self, name: "meeting")  // singleton: o ciclo não vaza
    config.userContentController.addUserScript(
      WKUserScript(
        source: i18n.isEmpty ? Self.extras : i18n + "\ni18n.start('page');i18n.setLanguage('pt');\n" + Self.extras,
        injectionTime: .atDocumentEnd, forMainFrameOnly: true))
    let v = CopilotWebView(frame: NSRect(origin: .zero, size: frame.size), configuration: config)
    v.setValue(false, forKey: "drawsBackground")
    v.autoresizingMask = [.width, .height]
    let bg = NSVisualEffectView(frame: v.frame)
    bg.material = .hudWindow
    bg.state = .active
    bg.appearance = NSAppearance(named: .darkAqua)
    bg.wantsLayer = true
    bg.layer?.cornerRadius = 18
    bg.layer?.masksToBounds = true
    bg.autoresizingMask = [.width, .height]
    bg.addSubview(v)
    let tracker = HoverTracker(frame: v.frame)
    tracker.autoresizingMask = [.width, .height]
    tracker.onMove = { [weak self, weak v] point in
      guard let v else { return }
      self?.js("hover", [point.x, v.bounds.height - point.y])
    }
    tracker.onExit = { [weak self] in self?.js("hover", [Double]()) }
    bg.addSubview(tracker)
    p.contentView = bg
    panel = p
    web = v
    installDragMonitor()
    v.loadHTMLString(html.replacingOccurrences(of: "/*ORBS*/", with: orbs), baseURL: nil)
    p.orderFrontRegardless()  // sem roubar o foco da chamada
  }

  private func close() {
    clock?.invalidate()
    clock = nil
    subscriptions.removeAll()
    settle?.cancel()
    serverPoll?.cancel()
    MeetingCopilotVoice.shared.stop()
    if let dragMonitor { NSEvent.removeMonitor(dragMonitor) }
    dragMonitor = nil
    web?.configuration.userContentController.removeScriptMessageHandler(forName: "meeting")
    panel?.orderOut(nil)
    panel = nil
    web = nil
    loaded = false
    running = false
  }

  private func resetSession() {
    serial = 0
    sentLines = [:]
    transcript = []
    askedSegments = []
    notes = ""
    memoryBrief = ""
    savedNoteId = nil
    answers = []
    server = nil
    serverAfter = nil
    minimized = false
    voicing = false
    began = Date()
  }

  private func js(_ call: String, _ value: Any = [String: Any]()) {
    let args: [Any] = [value]
    guard JSONSerialization.isValidJSONObject(args), let data = try? JSONSerialization.data(withJSONObject: args),
      let json = String(data: data, encoding: .utf8)
    else { return }
    web?.evaluateJavaScript("meeting.\(call)(...\(json))")
  }

  private func omi(_ call: String, _ value: Any) {
    let args: [Any] = [value]
    guard let data = try? JSONSerialization.data(withJSONObject: args), let json = String(data: data, encoding: .utf8)
    else { return }
    web?.evaluateJavaScript("window.omi?.\(call)(...\(json))")
  }

  /// O Atticus guarda posição e tamanho; aqui a altura pedida pela página e o canto de cima fixo bastam.
  private func size(_ h: Double, reveal: Int?) {
    guard let panel, let screen = panel.screen ?? NSScreen.main else { return }
    let bounds = screen.visibleFrame.insetBy(dx: 12, dy: 12)
    let top = min(max(panel.frame.maxY, bounds.minY), bounds.maxY)
    let most = max(1, top - bounds.minY)
    let want = h <= 0 ? min(expanded.height, most) : min(most, max(minimized ? 44 : 80, h))
    var f = panel.frame
    f.size = NSSize(width: min(minimized ? 116 : expanded.width, bounds.width), height: want)
    f.origin.y = top - want
    f.origin.x = min(max(f.minX, bounds.minX), bounds.maxX - f.width)
    panel.setFrame(f, display: true)
    if let reveal { js("settled", reveal) }
  }

  private func resize(_ w: Double, _ h: Double) {
    guard running, !minimized, let screen = panel?.screen ?? NSScreen.main else { return }
    let bounds = screen.visibleFrame.insetBy(dx: 12, dy: 12)
    expanded = NSSize(width: min(bounds.width, max(280, w)), height: min(bounds.height, max(380, h)))
    size(0, reveal: nil)
  }

  /// A página avisa `drag` no clique; o arraste em si é nativo, como no Atticus.
  private func installDragMonitor() {
    dragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) {
      [weak self] event in
      guard let self, let panel = self.panel, event.window === panel else { return event }
      switch event.type {
      case .leftMouseDown:
        self.mouseDown = NSEvent.mouseLocation
        self.dragOrigin = nil
      case .leftMouseDragged:
        guard let origin = self.dragOrigin, let down = self.mouseDown else { return event }
        let point = NSEvent.mouseLocation
        var f = origin
        f.origin.x += point.x - down.x
        f.origin.y += point.y - down.y
        panel.setFrameOrigin(f.origin)
        return nil
      case .leftMouseUp:
        let moved = self.dragOrigin != nil && self.dragOrigin?.origin != panel.frame.origin
        self.dragOrigin = nil
        self.mouseDown = nil
        if moved { return nil }
      default: break
      }
      return event
    }
  }

  // MARK: - Mensagens da página

  func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
    guard message.webView === web, let body = message.body as? [String: Any], let action = body["do"] as? String
    else { return }
    handle(action, body)
  }

  private func handle(_ action: String, _ b: [String: Any]) {
    switch action {
    case "ready": ready()
    case "drag": if mouseDown != nil { dragOrigin = panel?.frame }
    case "size": size(b["h"] as? Double ?? 0, reveal: b["reveal"] as? Int)
    case "resize": resize(b["w"] as? Double ?? 340, b["h"] as? Double ?? 650)
    case "compact":
      guard running else { return }
      minimized = b["on"] as? Bool ?? false
      panel?.contentView?.layer?.cornerRadius = minimized ? 22 : 18
      js("compact", minimized)
    case "focus":
      panel?.makeKey()
      js("focus")
    case "copy":
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(b["text"] as? String ?? "", forType: .string)
    case "brief": notes = String((b["text"] as? String ?? "").prefix(MeetingCopilotPrompt.briefLimit))
    case "stop": stop(paused: false)
    case "pause": stop(paused: true)
    case "resume": listen()
    case "save":
      persistNotes()
      close()
    case "delete", "deleteSaved": close()
    case "ask", "answer":
      guard running else { return }
      let id = b["id"] as? Int ?? nextId()
      let question = MeetingCopilotPrompt.portuguese(b["text"] as? String ?? "")
      if action == "ask" { js("question", row(id, question, auto: true)) }
      answer(id, question, manual: true)
    case "screen": explainScreen(MeetingCopilotPrompt.portuguese(b["text"] as? String ?? MeetingCopilotPrompt.explainScreen))
    case "voice":
      voicing = b["on"] as? Bool ?? false
    case "mute": MeetingCopilotVoice.shared.muted = b["on"] as? Bool ?? false
    case "meetings": NSApp.activate(ignoringOtherApps: true)
    default: break  // preparo do Atticus (agenda, arquivos, estilos) não existe no Omi
    }
  }

  private func ready() {
    guard !loaded else { return }
    loaded = true
    js("motion", NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    js("privacy", true)
    js("width", min(340, ((panel?.screen ?? NSScreen.main)?.visibleFrame.width ?? 364) - 24))
    omi("muted", MeetingCopilotVoice.shared.muted)
    listen()  // o Omi já está gravando a chamada: sem a tela de preparo do Atticus
    loadMemoryBrief()
  }

  private func listen() {
    guard loaded else { return }
    running = true
    js("listen")
    js("capturing")
    js("saving", true)
    clock?.invalidate()
    clock = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, self.running else { return }
        self.js("clock", Int(Date().timeIntervalSince(self.began)))
      }
    }
    subscriptions.removeAll()
    LiveTranscriptMonitor.shared.$segments
      .receive(on: DispatchQueue.main)
      .sink { [weak self] segments in MainActor.assumeIsolated { self?.segmentsChanged(segments) } }
      .store(in: &subscriptions)
    LiveNotesMonitor.shared.$notes
      .receive(on: DispatchQueue.main)
      .sink { [weak self] notes in MainActor.assumeIsolated { self?.omi("liveNotes", notes.map(\.text)) } }
      .store(in: &subscriptions)
    serverPoll?.cancel()
    serverPoll = Task { [weak self] in await self?.pollServer() }
  }

  private func stop(paused: Bool) {
    guard running else { return }
    running = false
    clock?.invalidate()
    subscriptions.removeAll()
    settle?.cancel()
    serverPoll?.cancel()
    MeetingCopilotVoice.shared.stop()
    js("stopped", paused)
    if !paused { persistNotes() }
  }

  // MARK: - Transcrição

  private func nextId() -> Int {
    serial += 1
    return serial
  }

  private func row(_ id: Int, _ text: String, auto: Bool, heard: Bool = false, speaker: String = "Alguém")
    -> [String: Any]
  {
    var r: [String: Any] = [
      "id": id, "text": text, "seconds": Int(Date().timeIntervalSince(began)), "speaker": speaker, "auto": auto,
    ]
    if heard { r["heard"] = true }
    return r
  }

  /// Todos os segmentos menos o último já estão fechados e viram linha; o último aparece como parcial.
  private func segmentsChanged(_ segments: [SpeakerSegment]) {
    guard running else { return }
    if segments.isEmpty {
      sentLines = [:]
      return
    }
    if server != nil {
      // A transcrição vem da extensão; do Omi fica só a pergunta por voz. O que passou não volta depois.
      for segment in segments { sentLines[segment.id] = true }
      if voicing, let last = segments.last, last.isUser { js("heard", last.text) }
      return
    }
    for (index, segment) in segments.enumerated() {
      let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { continue }
      let last = index == segments.count - 1
      if last {
        guard sentLines[segment.id] == nil else { continue }
        if voicing && segment.isUser {
          js("heard", text)
          continue
        }
        js("partial", ["mic": segment.isUser, "text": text] as [String: Any])
        if !segment.isUser { scheduleCandidate(segment.id, text) }
      } else if sentLines[segment.id] == nil {
        sentLines[segment.id] = true
        if voicing && segment.isUser { continue }  // pergunta por voz, não entra na transcrição
        js("partial", ["mic": segment.isUser, "text": ""] as [String: Any])
        let id = nextId()
        js("line", ["id": id, "text": text, "seconds": Int(segment.start), "mic": segment.isUser] as [String: Any])
        transcript.append(.init(at: Date(), mine: segment.isUser, text: text))
        if !segment.isUser { candidate(segment.id, text, lineId: id) }
      }
    }
  }

  /// A fala ainda aberta que termina em "?" e para de mudar por 1,2 s já dispara, sem esperar o próximo segmento.
  private func scheduleCandidate(_ segmentId: String, _ text: String) {
    settle?.cancel()
    guard MeetingCopilotPrompt.isCandidate(text), !askedSegments.contains(segmentId) else { return }
    let item = DispatchWorkItem { [weak self] in
      MainActor.assumeIsolated {
        guard let self, self.running else { return }
        self.candidate(segmentId, text, lineId: nil)
      }
    }
    settle = item
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: item)
  }

  private func candidate(_ segmentId: String, _ text: String, lineId: Int?, speaker: String = "Alguém") {
    guard MeetingCopilotPrompt.isCandidate(text), askedSegments.insert(segmentId).inserted else { return }
    let id = lineId ?? nextId()
    js("question", row(id, text, auto: true, heard: true, speaker: speaker))
    answer(id, text, manual: false)
  }

  // MARK: - Trechos da extensão (servidor de reuniões)

  /// A cada 30 s confere se a extensão está gravando uma reunião; enquanto estiver, busca os trechos novos a cada 3 s.
  private func pollServer() async {
    guard let key = MeetingCopilotServer.key else { return }
    var checked = Date.distantPast
    while !Task.isCancelled, running {
      if Date().timeIntervalSince(checked) >= 30 {
        checked = Date()
        do {
          let found = try await MeetingCopilotServer.activeMeeting(key: key)
          guard running, !Task.isCancelled else { return }
          attach(found)
        } catch {
          log("MeetingCopilot: servidor de reuniões indisponível (\(type(of: error)))")
        }
      }
      var more = false
      if let meeting = server {
        do {
          let page = try await MeetingCopilotServer.trechos(meeting: meeting.id, after: serverAfter, key: key)
          guard running, !Task.isCancelled, server == meeting else { continue }
          serverLines(page.items, meeting)
          more = page.more
        } catch {
          log("MeetingCopilot: trechos indisponíveis (\(type(of: error)))")
        }
      }
      if !more { try? await Task.sleep(for: .seconds(3)) }
    }
  }

  private func attach(_ meeting: MeetingCopilotServer.Meeting?) {
    guard meeting != server else { return }
    let had = server != nil
    server = meeting
    serverAfter = nil
    guard meeting != nil else {
      if had { js("error", "A extensão parou de gravar; seguindo com a transcrição do Omi") }
      return
    }
    settle?.cancel()
    js("partial", ["mic": false, "text": ""] as [String: Any])
    js("partial", ["mic": true, "text": ""] as [String: Any])
    js("error", "Transcrição com nomes, vinda da extensão de reuniões")
  }

  private func serverLines(_ items: [MeetingCopilotServer.Trecho], _ meeting: MeetingCopilotServer.Meeting) {
    let givenName = AuthService.shared.givenName
    for t in items {
      serverAfter = max(serverAfter ?? -1, t.seq)
      let text = t.text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { continue }
      let mine = MeetingCopilotServer.isMine(t.speaker, givenName: givenName)
      let who = t.speaker ?? "Participante"
      let id = nextId()
      js("line", ["id": id, "text": text, "seconds": t.startMs / 1000, "mic": mine] as [String: Any])
      if !mine { omi("speaker", ["id": id, "who": who] as [String: Any]) }
      let at = meeting.start.addingTimeInterval(Double(t.startMs) / 1000)
      transcript.append(.init(at: at, mine: mine, text: text, who: mine ? nil : who))
      // Ao entrar no meio da reunião, pergunta antiga não vira resposta automática
      if !mine, Date().timeIntervalSince(at) < 90 { candidate("s\(t.seq)", text, lineId: id, speaker: who) }
    }
  }

  // MARK: - Respostas

  private var context: String {
    let live = LiveNotesMonitor.shared.notes.map { "- \($0.text)" }.joined(separator: "\n")
    return [memoryBrief, notes, live.isEmpty ? "" : "Live notes:\n" + live]
      .filter { !$0.isEmpty }.joined(separator: "\n\n")
  }

  private func answer(_ id: Int, _ question: String, manual: Bool, image: Data? = nil) {
    let prompt = MeetingCopilotPrompt.request(
      question: question, brief: context, transcript: transcript, manual: manual)
    js("thinking", id)
    Task { [weak self] in
      do {
        let client = try GeminiClient(model: Self.answerModel, lane: .liveNotes, workload: .interactive)
        let text = try await client.sendTextRequest(
          prompt: prompt, systemPrompt: MeetingCopilotPrompt.system, maxRetries: 1, timeout: 30,
          image: image.map { (data: $0, mimeType: "image/jpeg") })
        guard let self, self.running else { return }
        guard let parsed = MeetingCopilotPrompt.parse(text) else {
          self.js("answer", ["id": id, "error": "Sem resposta do Gemini"] as [String: Any])
          return
        }
        var out: [String: Any] = ["id": id, "kind": parsed.kind, "lines": parsed.lines]
        if let reason = parsed.reason { out["reason"] = reason }
        if parsed.general { out["general"] = true }
        self.js("answer", out)
        if parsed.kind == "answer", let first = parsed.lines.first {
          self.answers.append((question, parsed.lines))
          MeetingCopilotVoice.shared.speak(first)
        }
      } catch {
        log("MeetingCopilot: resposta falhou (\(type(of: error)))")
        self?.js("answer", ["id": id, "error": "Não consegui responder agora"] as [String: Any])
      }
    }
  }

  private func explainScreen(_ question: String) {
    guard running else { return }
    guard let jpeg = ScreenCaptureManager.captureScreenJPEG(quality: 0.65) else {
      js("error", "Permita a Gravação de Tela para o Omi nos Ajustes")
      return
    }
    let id = nextId()
    js("question", row(id, question, auto: true))
    answer(id, question, manual: true, image: jpeg)
  }

  /// Decisões e pendências de conversas anteriores com o mesmo evento da agenda (sem chamada de modelo).
  private func loadMemoryBrief() {
    guard let owner = RuntimeOwnerIdentity.captureAuthorizationSnapshot() else { return }
    Task { [weak self] in
      // A reunião já começou: o compositor só olha eventos futuros, então recua meia hora.
      let now = Date().addingTimeInterval(-30 * 60)
      let events = await SystemCalendarMeetingContextService.shared.upcomingAuthorizedEvents(
        now: now, horizon: MeetingMemoryBriefComposer.leadWindow)
      guard !events.isEmpty else { return }
      do {
        let conversations = try await APIClient.shared.getConversations(
          limit: 100, statuses: [.completed],
          startDate: now.addingTimeInterval(-MeetingMemoryBriefComposer.lookback), endDate: Date(),
          authorizationSnapshot: owner)
        guard let brief = MeetingMemoryBriefComposer.compose(events: events, conversations: conversations, now: now)
        else { return }
        let facts = brief.facts.map { "- \($0.kind.label): \($0.text)" }.joined(separator: "\n")
        self?.memoryBrief = "Meeting: \(brief.title)\nFrom \"\(brief.sourceConversationTitle)\":\n\(facts)"
      } catch {
        log("MeetingCopilot: briefing indisponível (\(type(of: error)))")
      }
    }
  }

  /// Notas manuais e respostas ficam na conversa do Omi desta reunião (`NoteStorage`, por sessão).
  private func persistNotes() {
    guard let sessionId = AppState.current?.currentSessionId else { return }
    let manual = notes.trimmingCharacters(in: .whitespacesAndNewlines)
    let pending = answers
    answers = []
    let noteId = savedNoteId
    Task { [weak self] in
      do {
        if !manual.isEmpty {
          if let noteId {
            try await NoteStorage.shared.updateNote(id: noteId, text: manual)
          } else {
            let record = try await NoteStorage.shared.createNote(
              sessionId: sessionId, text: manual, isAiGenerated: false)
            self?.savedNoteId = record.id
          }
        }
        for item in pending {
          let text = "Pergunta: \(item.question)\nResposta: \(item.lines.joined(separator: " "))"
          try await NoteStorage.shared.createNote(sessionId: sessionId, text: text, isAiGenerated: true)
        }
      } catch {
        log("MeetingCopilot: não salvou as notas (\(type(of: error)))")
      }
    }
  }

  /// Botão de silenciar a voz, a lista do LiveNotes na aba Notas, o nome de quem falou nas linhas da extensão
  /// e o português dos textos montados na hora (o `i18n.js` só troca frase inteira), sem editar o HTML do Atticus.
  private static let extras = """
    (() => {
      const post = m => window.webkit?.messageHandlers.meeting.postMessage(m);
      let muted = false;
      const b = document.createElement('button');
      b.id = 'omimute'; b.className = 'quiet icon'; b.hidden = true;
      const paint = () => { b.textContent = muted ? '🔇' : '🔊'; b.title = muted ? 'Ativar voz' : 'Silenciar voz';
        b.setAttribute('aria-label', b.title); };
      b.onclick = () => { muted = !muted; paint(); post({do: 'mute', on: muted}); };
      paint();
      const minimize = document.getElementById('minimize');
      minimize?.parentNode.insertBefore(b, minimize);
      new MutationObserver(() => { b.hidden = !!minimize?.hidden; }).observe(minimize, {attributes: true});
      const list = document.createElement('div');
      list.id = 'omilivenotes'; list.className = 'note';
      list.style.whiteSpace = 'pre-wrap'; list.style.marginTop = '8px';
      document.getElementById('brief')?.after(list);

      const rules = [
        [/^Listening · /, 'Ouvindo · '], [/^Getting ready$/, 'Preparando'],
        [/^1 line heard$/, '1 fala ouvida'], [/^(\\d+) lines heard$/, '$1 falas ouvidas'],
        [/^Someone else asked · /, 'Alguém perguntou · '], [/^(.+) asked · /, '$1 perguntou · '],
        [/^You · /, 'Você · '], [/^Answer: /, 'Responder: '],
        [/^Restore meeting panel · Listening$/, 'Restaurar o painel · Ouvindo'],
        [/^Restore meeting panel · /, 'Restaurar o painel · '], [/^Preview of /, 'Prévia de '],
      ];
      const fix = t => rules.reduce((s, [re, to]) => s.replace(re, to), t);
      const attrs = ['title', 'aria-label', 'alt', 'placeholder'];
      const fixNode = n => {
        if (n.nodeType === Node.TEXT_NODE) {
          if (n.parentElement?.closest('textarea,script,style')) return;
          const to = fix(n.nodeValue); if (to !== n.nodeValue) n.nodeValue = to; return;
        }
        if (n.nodeType !== Node.ELEMENT_NODE) return;
        for (const el of [n, ...n.querySelectorAll('*')]) {
          for (const a of attrs) if (el.hasAttribute(a)) {
            const v = el.getAttribute(a), to = fix(v); if (to !== v) el.setAttribute(a, to);
          }
          for (const c of el.childNodes) if (c.nodeType === Node.TEXT_NODE) fixNode(c);
        }
      };
      const watch = new MutationObserver(records => {
        watch.disconnect();
        for (const r of records) {
          if (r.type === 'childList') r.addedNodes.forEach(fixNode);
          else if (r.type === 'characterData') fixNode(r.target);
          else fixNode(r.target);
        }
        start();
      });
      const start = () => watch.observe(document.body, {childList: true, subtree: true, characterData: true,
        attributes: true, attributeFilter: attrs});
      fixNode(document.body); start();

      // Copiar a transcrição como está na tela, com os nomes (o original escreve You/Them)
      document.addEventListener('click', e => {
        if (!e.target.closest?.('#endcopy')) return;
        e.preventDefault(); e.stopPropagation();
        const text = [...document.querySelectorAll('#lines .line')].map(l =>
          `${l.querySelector('.t')?.textContent || ''}  ${l.querySelector('.text')?.textContent || ''}`).join('\\n');
        post({do: 'copy', text});
        const toast = document.getElementById('toast');
        if (toast) { toast.textContent = 'Transcrição copiada'; toast.hidden = false; setTimeout(() => toast.hidden = true, 4000); }
      }, true);

      window.omi = {
        muted(on) { muted = on; paint(); },
        liveNotes(items) {
          list.textContent = items.length ? 'LiveNotes\\n' + items.map(t => '• ' + t).join('\\n') : '';
        },
        speaker({id, who}) {
          const text = document.querySelector(`#lines [data-id="${id}"] .text`);
          if (!text || text.querySelector('b')) return;
          const name = document.createElement('b'); name.textContent = who + ' · '; text.prepend(name);
        }
      };
    })();
    """
}

/// Painel que aceita teclado (campo de pergunta) sem ativar o Omi.
private final class CopilotPanel: NSPanel {
  override var canBecomeKey: Bool { true }
}

private final class CopilotWebView: WKWebView {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Painel não ativável não recebe hover no WebKit; repassa a posição do mouse para a página.
private final class HoverTracker: NSView {
  var onMove: ((NSPoint) -> Void)?
  var onExit: (() -> Void)?
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach(removeTrackingArea)
    addTrackingArea(
      NSTrackingArea(
        rect: .zero, options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect], owner: self))
  }
  override func mouseMoved(with event: NSEvent) { onMove?(convert(event.locationInWindow, from: nil)) }
  override func mouseExited(with event: NSEvent) { onExit?() }
}
