//
//  JarvisEstatisticas.swift — a página Estatísticas: conversas, reuniões, minutos gravados e pedidos
//  ao Jarvis, por dia, e onde você usa.
//
//  Layout portado do Coucou (MIT, © 2026 Louis Raillé, aviso em THIRD_PARTY_COUCOU_LICENSE):
//  `NotchBuddy/Sources/App/FlowHubInsights.swift` (HubInsightsPage, HubStatCard, HubBars, HubAppBars).
//

import Foundation
import GRDB
import OmiTheme
import SwiftUI

// MARK: - Dados

/// Uma gravação local (linha de `transcription_sessions` no `omi.db`).
struct JarvisGravacao: Equatable, Sendable {
  let inicio: Date
  let fim: Date?
  let origem: String
  let reuniao: Bool
}

/// Uma linha do `GET /jarvis/historico` em que o Gabriel pediu algo.
struct JarvisPedido: Equatable, Sendable {
  let criadoEm: Date
  let origem: String
}

enum JarvisPeriodo: String, CaseIterable, Identifiable {
  case semana, mes, tudo
  var id: String { rawValue }

  var rotulo: String {
    switch self {
    case .semana: return "Semana"
    case .mes: return "Mês"
    case .tudo: return "Tudo"
    }
  }

  /// Dias que o gráfico mostra.
  var diasNoGrafico: Int { self == .semana ? 7 : 30 }

  func inicio(hoje: Date, calendario: Calendar) -> Date? {
    let dia = calendario.startOfDay(for: hoje)
    switch self {
    case .semana: return calendario.date(byAdding: .day, value: -6, to: dia)
    case .mes: return calendario.date(byAdding: .day, value: -29, to: dia)
    case .tudo: return nil
    }
  }
}

struct JarvisResumo: Equatable {
  struct Dia: Equatable {
    let data: Date
    let minutos: Int
  }

  var conversas = 0
  var reunioes = 0
  var minutos = 0
  /// nil quando não há chave do Jarvis ou o servidor não respondeu: o cartão mostra "—".
  var pedidos: Int?
  var porDia: [Dia] = []
  /// "Onde você usa": rótulo e quantidade, do maior para o menor.
  var onde: [(rotulo: String, quantidade: Int)] = []

  static func == (a: JarvisResumo, b: JarvisResumo) -> Bool {
    a.conversas == b.conversas && a.reunioes == b.reunioes && a.minutos == b.minutos
      && a.pedidos == b.pedidos && a.porDia == b.porDia
      && a.onde.map(\.rotulo) == b.onde.map(\.rotulo) && a.onde.map(\.quantidade) == b.onde.map(\.quantidade)
  }

  /// Junta as gravações e os pedidos do período. Gravação sem fim conta como conversa, sem minutos.
  static func agregar(
    gravacoes: [JarvisGravacao], pedidos: [JarvisPedido]?, periodo: JarvisPeriodo,
    hoje: Date = Date(), calendario: Calendar = .current
  ) -> JarvisResumo {
    let desde = periodo.inicio(hoje: hoje, calendario: calendario)
    let noPeriodo = gravacoes.filter { desde == nil || $0.inicio >= desde! }
    let pedidosNoPeriodo = pedidos?.filter { desde == nil || $0.criadoEm >= desde! }

    func minutos(_ g: JarvisGravacao) -> Int {
      guard let fim = g.fim, fim > g.inicio else { return 0 }
      return Int((fim.timeIntervalSince(g.inicio) / 60).rounded())
    }

    var resumo = JarvisResumo()
    resumo.conversas = noPeriodo.count
    resumo.reunioes = noPeriodo.filter(\.reuniao).count
    resumo.minutos = noPeriodo.map(minutos).reduce(0, +)
    resumo.pedidos = pedidosNoPeriodo?.count

    let hojeInicio = calendario.startOfDay(for: hoje)
    var minutosPorDia: [Date: Int] = [:]
    for g in gravacoes {
      minutosPorDia[calendario.startOfDay(for: g.inicio), default: 0] += minutos(g)
    }
    resumo.porDia = (0..<periodo.diasNoGrafico).reversed().compactMap { atras in
      guard let dia = calendario.date(byAdding: .day, value: -atras, to: hojeInicio) else { return nil }
      return Dia(data: dia, minutos: minutosPorDia[dia] ?? 0)
    }

    var onde: [String: Int] = [:]
    for g in noPeriodo { onde[rotuloGravacao(g.origem), default: 0] += 1 }
    for p in pedidosNoPeriodo ?? [] { onde["Jarvis (\(rotuloOrigemJarvis(p.origem)))", default: 0] += 1 }
    resumo.onde = onde.map { ($0.key, $0.value) }
      .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }
      .map { (rotulo: $0.0, quantidade: $0.1) }
    return resumo
  }

  static func rotuloGravacao(_ origem: String) -> String {
    switch origem {
    case "desktop": return "Gravação no Mac"
    case "omi": return "Colar Omi"
    default: return "Gravação (\(origem))"
    }
  }

  static func rotuloOrigemJarvis(_ origem: String) -> String {
    switch origem.lowercased() {
    case "mac": return "Mac"
    case "whatsapp": return "WhatsApp"
    default: return origem
    }
  }

  /// Lê a resposta do histórico: só as linhas em que o Gabriel falou contam como pedido.
  static func pedidos(doHistorico dados: Data) -> [JarvisPedido]? {
    guard let linhas = try? JSONSerialization.jsonObject(with: dados) as? [[String: Any]] else {
      return nil
    }
    return linhas.compactMap { linha in
      guard linha["papel"] as? String == "gabriel",
        let criado = linha["criado_em"] as? String,
        let data = dataDoServidor(criado)
      else { return nil }
      return JarvisPedido(criadoEm: data, origem: linha["origem"] as? String ?? "mac")
    }
  }

  /// "2026-11-17T00:56:21.903286+00:00": o servidor manda sempre em UTC; lê até os segundos.
  static func dataDoServidor(_ texto: String) -> Date? {
    let formato = DateFormatter()
    formato.locale = Locale(identifier: "en_US_POSIX")
    formato.timeZone = TimeZone(identifier: "UTC")
    formato.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    return formato.date(from: String(texto.prefix(19)))
  }
}

// MARK: - Fontes

enum JarvisFontesEstatisticas {
  static let servicoChave = "com.omi.desktop.jarvis"
  static let contaChave = "chave"
  static let urlHistorico = URL(string: "https://smarten-jarvis.fly.dev/jarvis/historico?horas=720")!

  /// As gravações locais que não foram descartadas nem apagadas.
  static func gravacoes() async -> [JarvisGravacao] {
    guard let banco = await RewindDatabase.shared.getDatabaseQueue() else { return [] }
    do {
      return try await banco.read { db in
        try Row.fetchAll(
          db,
          sql: """
            SELECT startedAt, finishedAt, source, conversationRole FROM transcription_sessions
            WHERE COALESCE(deleted, 0) = 0 AND COALESCE(discarded, 0) = 0
            """
        ).compactMap { linha in
          guard let inicio: Date = linha["startedAt"] else { return nil }
          return JarvisGravacao(
            inicio: inicio, fim: linha["finishedAt"], origem: linha["source"] ?? "desktop",
            reuniao: (linha["conversationRole"] as String?) == "meeting")
        }
      }
    } catch {
      log("JarvisEstatisticas: falha ao ler transcription_sessions: \(error.localizedDescription)")
      return []
    }
  }

  /// Os pedidos ao Jarvis dos últimos 30 dias; nil sem chave ou sem resposta.
  static func pedidos() async -> [JarvisPedido]? {
    guard let chave = DesktopKeychainStore.string(service: servicoChave, account: contaChave) else {
      return nil
    }
    var pedido = URLRequest(url: urlHistorico, timeoutInterval: 15)
    pedido.setValue("Bearer \(chave)", forHTTPHeaderField: "Authorization")
    guard let (dados, resposta) = try? await URLSession.shared.data(for: pedido),
      (resposta as? HTTPURLResponse)?.statusCode == 200
    else { return nil }
    return JarvisResumo.pedidos(doHistorico: dados)
  }
}

// MARK: - Página

struct JarvisEstatisticasPagina: View {
  @State private var periodo: JarvisPeriodo = .mes
  @State private var gravacoes: [JarvisGravacao] = []
  @State private var pedidos: [JarvisPedido]?

  var body: some View {
    let resumo = JarvisResumo.agregar(gravacoes: gravacoes, pedidos: pedidos, periodo: periodo)
    JarvisPaginaBase(
      titulo: "Estatísticas", subtitulo: "O que você gravou e pediu ao Jarvis, e onde.",
      cor: JarvisHubTema.verde
    ) {
      Picker("", selection: $periodo) {
        ForEach(JarvisPeriodo.allCases) { Text($0.rotulo).tag($0) }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .fixedSize()
    } content: {
      HStack(spacing: 14) {
        JarvisCartaoNumero(rotulo: "Conversas", valor: "\(resumo.conversas)")
        JarvisCartaoNumero(rotulo: "Reuniões", valor: "\(resumo.reunioes)")
        JarvisCartaoNumero(rotulo: "Minutos gravados", valor: Self.duracao(minutos: resumo.minutos))
        JarvisCartaoNumero(
          rotulo: "Pedidos ao Jarvis", valor: resumo.pedidos.map { "\($0)" } ?? "—",
          nota: periodo == .tudo ? "últimos 30 dias" : nil)
      }
      HStack(alignment: .top, spacing: 14) {
        JarvisCartao(padding: 20) {
          Text("Minutos por dia").font(.system(size: 14, weight: .bold))
          JarvisBarras(dias: resumo.porDia)
            .frame(height: 200)
        }
        .frame(maxWidth: .infinity)
        JarvisCartao(padding: 20) {
          Text("Onde você usa").font(.system(size: 14, weight: .bold))
          JarvisBarrasOnde(itens: resumo.onde)
        }
        .frame(width: 300)
      }
      Text("Tudo é lido no seu Mac; só os pedidos vêm do servidor do Jarvis.")
        .font(.system(size: 12))
        .foregroundColor(JarvisHubTema.apagado)
    }
    .task {
      async let locais = JarvisFontesEstatisticas.gravacoes()
      async let remotos = JarvisFontesEstatisticas.pedidos()
      gravacoes = await locais
      pedidos = await remotos
    }
  }

  /// "3 h 52" ou "18 min".
  nonisolated static func duracao(minutos: Int) -> String {
    minutos < 60 ? "\(minutos) min" : String(format: "%d h %02d", minutos / 60, minutos % 60)
  }
}

private struct JarvisCartaoNumero: View {
  let rotulo: String
  let valor: String
  var nota: String? = nil

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(rotulo)
        .font(.system(size: 12))
        .foregroundColor(JarvisHubTema.secundario)
      Text(valor)
        .font(.system(size: 28, weight: .bold))
        .tracking(-0.6)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.6)
      Text(nota ?? " ")
        .font(.system(size: 12))
        .foregroundColor(JarvisHubTema.secundario)
        .lineLimit(1)
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(JarvisHubTema.cartao))
    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(JarvisHubTema.linha))
  }
}

/// Minutos por dia, hoje em laranja cheio.
private struct JarvisBarras: View {
  let dias: [JarvisResumo.Dia]

  var body: some View {
    let topo = max(1, dias.map(\.minutos).max() ?? 1)
    let rotuloACada = dias.count > 10 ? 5 : 1
    GeometryReader { geo in
      HStack(alignment: .bottom, spacing: dias.count > 10 ? 4 : 10) {
        ForEach(Array(dias.enumerated()), id: \.offset) { indice, dia in
          let ehHoje = indice == dias.count - 1
          VStack(spacing: 7) {
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
              .fill(ehHoje ? JarvisHubTema.destaque : JarvisHubTema.destaque.opacity(0.35))
              .frame(
                height: max(
                  dia.minutos > 0 ? 4 : 2, (geo.size.height - 24) * CGFloat(dia.minutos) / CGFloat(topo)))
              .help("\(dia.minutos) min")
            Text(indice % rotuloACada == 0 || ehHoje ? Self.rotulo(dia.data, curto: dias.count > 10) : " ")
              .font(.system(size: 10.5, weight: ehHoje ? .bold : .regular))
              .foregroundColor(ehHoje ? JarvisHubTema.texto : JarvisHubTema.apagado)
              .lineLimit(1)
              .fixedSize()
              .frame(height: 14)
          }
          .frame(maxWidth: .infinity)
        }
      }
    }
  }

  static func rotulo(_ data: Date, curto: Bool) -> String {
    curto
      ? data.formatted(.dateTime.day())
      : data.formatted(.dateTime.weekday(.narrow).locale(Locale(identifier: "pt_BR")))
  }
}

private struct JarvisBarrasOnde: View {
  let itens: [(rotulo: String, quantidade: Int)]

  var body: some View {
    let total = max(1, itens.map(\.quantidade).reduce(0, +))
    if itens.isEmpty {
      Text("Nada registrado neste período.")
        .font(.system(size: 13))
        .foregroundColor(JarvisHubTema.secundario)
    }
    ForEach(Array(itens.prefix(6)), id: \.rotulo) { item in
      let parte = Double(item.quantidade) / Double(total)
      VStack(alignment: .leading, spacing: 5) {
        HStack {
          Text(item.rotulo).font(.system(size: 13)).lineLimit(1)
          Spacer()
          Text(parte.formatted(.percent.precision(.fractionLength(0))))
            .font(.system(size: 13))
            .foregroundColor(JarvisHubTema.secundario)
            .monospacedDigit()
        }
        GeometryReader { geo in
          ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.06))
            Capsule().fill(JarvisHubTema.destaque).frame(width: max(4, geo.size.width * parte))
          }
        }
        .frame(height: 6)
      }
    }
  }
}
