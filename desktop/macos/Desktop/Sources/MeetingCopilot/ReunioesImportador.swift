import Foundation

/// Leva as reuniões encerradas que a extensão do Meet mandou para o Cérebro para Conversas, como
/// conversa do Omi na coleção "Reuniões", com cada participante como pessoa do Omi. O
/// `client_session_id` é o id da reunião no Cérebro: reenviar não duplica.
@MainActor
final class ReunioesImportador {
  static let shared = ReunioesImportador()
  static let colecao = "Reuniões"
  private static let enviadasKey = "reunioesImportadas"
  /// Reunião mais velha que isso fica de fora: o processamento do Omi tira tarefas e memórias de
  /// cada conversa nova, e reunião antiga encheria Tarefas de coisa vencida.
  static let janela: TimeInterval = 7 * 24 * 3600
  /// O backend aceita 30 envios por hora; 5 a cada 15 minutos fica abaixo.
  static let porRodada = 5
  /// O backend aceita até 500 segmentos por conversa.
  static let maxSegmentos = 500

  private var timer: Timer?
  private var rodando = false

  func iniciar() {
    guard timer == nil else { return }
    timer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { _ in
      Task { @MainActor in await ReunioesImportador.shared.rodar() }
    }
    Task { try? await Task.sleep(for: .seconds(60)); await rodar() }
  }

  func rodar() async {
    guard !rodando, AuthService.shared.isSignedIn, let key = MeetingCopilotServer.key else { return }
    rodando = true
    defer { rodando = false }
    var enviadas = Set(UserDefaults.standard.stringArray(forKey: Self.enviadasKey) ?? [])
    do {
      let result = try await MeetingCopilotServer.call(
        "listar_reunioes", ["estado": "encerrada", "limite": 30], key: key)
      let pendentes = Self.pendentes(
        in: result["reunioes"] as? [[String: Any]] ?? [], enviadas: enviadas, now: Date())
      guard !pendentes.isEmpty else { return }
      let pasta = try await colecao()
      var pessoas = Dictionary(
        lastWriteWins: try await APIClient.shared.getPeople().map { (Self.chave($0.name), $0.id) })
      for reuniao in pendentes.prefix(Self.porRodada) {
        let trechos = try await Self.transcricao(meeting: reuniao.id, key: key)
        guard !trechos.isEmpty else { continue }
        for nome in Self.participantes(trechos, givenName: AuthService.shared.givenName)
        where pessoas[Self.chave(nome)] == nil {
          pessoas[Self.chave(nome)] = try await APIClient.shared.createPerson(name: nome).id
        }
        _ = try await APIClient.shared.createConversationFromSegments(
          Self.pedido(reuniao, trechos: trechos, pessoas: pessoas, pasta: pasta, givenName: AuthService.shared.givenName))
        enviadas.insert(reuniao.id)
        UserDefaults.standard.set(Array(enviadas), forKey: Self.enviadasKey)
        log("Reuniões: \"\(reuniao.titulo)\" foi para Conversas")
      }
    } catch {
      log("Reuniões: importação falhou: \(error.localizedDescription)")
    }
  }

  private func colecao() async throws -> String {
    let pastas = try await APIClient.shared.getFolders()
    if let pasta = pastas.first(where: { $0.name == Self.colecao }) { return pasta.id }
    return try await APIClient.shared.createFolder(name: Self.colecao).id
  }

  // MARK: - Puro, testado

  struct Reuniao: Equatable {
    let id: String
    let titulo: String
    let inicio: Date
    let fim: Date
  }

  /// Encerradas, da extensão (sem as "Omi dd/mm", que já são conversas do Omi), dentro da janela e
  /// ainda não enviadas, das mais velhas para as mais novas.
  static func pendentes(in meetings: [[String: Any]], enviadas: Set<String>, now: Date) -> [Reuniao] {
    meetings.compactMap { m -> Reuniao? in
      guard m["estado"] as? String == "encerrada", let id = m["id"] as? String, !enviadas.contains(id),
        let titulo = m["titulo"] as? String, !titulo.hasPrefix("Omi "),
        let inicio = (m["iniciada_em"] as? String).flatMap(MeetingCopilotServer.date),
        now.timeIntervalSince(inicio) < janela
      else { return nil }
      let fim = (m["encerrada_em"] as? String).flatMap(MeetingCopilotServer.date) ?? inicio
      return Reuniao(id: id, titulo: titulo, inicio: inicio, fim: max(fim, inicio))
    }
    .sorted { $0.inicio < $1.inicio }
  }

  /// Os outros participantes, na ordem em que falaram; você fica de fora (é o `is_user`).
  static func participantes(_ trechos: [MeetingCopilotServer.Trecho], givenName: String) -> [String] {
    var vistos = Set<String>()
    return trechos.compactMap(\.speaker).filter {
      !MeetingCopilotServer.isMine($0, givenName: givenName) && vistos.insert(chave($0)).inserted
    }
  }

  static func pedido(
    _ r: Reuniao, trechos: [MeetingCopilotServer.Trecho], pessoas: [String: String], pasta: String?,
    givenName: String
  ) -> APIClient.CreateConversationFromSegmentsRequest {
    let iso = ISO8601DateFormatter()
    let nomes = participantes(trechos, givenName: givenName)
    var request = APIClient.CreateConversationFromSegmentsRequest(
      transcript_segments: segmentos(trechos, pessoas: pessoas, nomes: nomes, givenName: givenName),
      source: "external_integration", started_at: iso.string(from: r.inicio), finished_at: iso.string(from: r.fim),
      language: "pt", client_conversation_id: "cerebro-\(r.id)", conversation_role: "meeting",
      conversation_finalization_reason: nil, client_processing: nil, captureEvidence: nil)
    request.calendar_meeting_context = .init(
      calendar_event_id: "cerebro-\(r.id)", title: r.titulo, participants: nomes.map { .init(name: $0) },
      platform: "Google Meet", start_time: iso.string(from: r.inicio),
      duration_minutes: min(1440, Int(r.fim.timeIntervalSince(r.inicio) / 60)))
    request.folder_id = pasta
    return request
  }

  /// Falas seguidas da mesma pessoa viram um segmento só; se ainda passar de 500, junta vizinhos.
  static func segmentos(
    _ trechos: [MeetingCopilotServer.Trecho], pessoas: [String: String], nomes: [String], givenName: String
  ) -> [APIClient.UploadSegment] {
    var falas: [(speaker: String?, start: Int, text: String)] = []
    for t in trechos {
      if let ultima = falas.last, ultima.speaker == t.speaker {
        falas[falas.count - 1].text += " " + t.text
      } else {
        falas.append((t.speaker, t.startMs, t.text))
      }
    }
    let passo = Int((Double(falas.count) / Double(maxSegmentos)).rounded(.up))
    if passo > 1 {
      falas = stride(from: 0, to: falas.count, by: passo).map { i in
        let grupo = falas[i..<min(i + passo, falas.count)]
        let texto = grupo.map { g in g.speaker.map { "\($0): \(g.text)" } ?? g.text }.joined(separator: " ")
        return (grupo.first!.speaker, grupo.first!.start, texto)
      }
    }
    return falas.enumerated().map { i, f in
      let fim = i + 1 < falas.count ? falas[i + 1].start : f.start + 3000
      let meu = MeetingCopilotServer.isMine(f.speaker, givenName: givenName)
      // Você é o falante 0; os outros seguem a ordem de `nomes`, sem nome fica num número à parte.
      let indice = meu ? 0 : f.speaker.flatMap { nome in nomes.firstIndex { chave($0) == chave(nome) } }.map { $0 + 1 }
        ?? nomes.count + 1
      return APIClient.UploadSegment(
        text: f.text, speaker: String(format: "SPEAKER_%02d", indice), speaker_id: indice, is_user: meu,
        person_id: meu ? nil : f.speaker.flatMap { pessoas[chave($0)] },
        start: Double(f.start) / 1000, end: Double(max(fim, f.start + 500)) / 1000)
    }
  }

  static func chave(_ nome: String) -> String {
    nome.trimmingCharacters(in: .whitespaces).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
  }

  // ponytail: no máximo 40 páginas de 200 trechos; reunião maior entra cortada
  static func transcricao(meeting: String, key: String) async throws -> [MeetingCopilotServer.Trecho] {
    var todos: [MeetingCopilotServer.Trecho] = []
    var after: Int?
    for _ in 0..<40 {
      let pagina = try await MeetingCopilotServer.trechos(meeting: meeting, after: after, key: key)
      todos += pagina.items
      guard pagina.more, let ultimo = pagina.items.last?.seq else { break }
      after = ultimo
    }
    return todos
  }
}
