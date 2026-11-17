//
//  JarvisTarefas.swift — a página Tarefas: as demandas do comando.smarten.digital na matriz urgente/importante.
//
//  Lê `GET /jarvis/tarefas` e escreve `POST /jarvis/tarefas/<id>` (concluir, prazo, quadrante), que no Fly passam
//  por `jarvis_mudar_demanda` e gravam o histórico em `demandas_eventos`. O app não leva a service key.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Dados e regra (puro, testado)

struct JarvisDemanda: Decodable, Identifiable, Equatable, Sendable {
  let id: Int
  let titulo: String
  var resumo: String?
  var situacao: String
  var responsavel: String?
  var prazo: String?
  var quadrante: String?
  var venceu: Bool
  var parada: Bool
  var cliente: String?
}

/// A regra do comando (`hoje-puro.ts`): o quadrante é a coluna gerada da migration 082.
enum JarvisQuadrante: String, CaseIterable, Identifiable, Sendable {
  case q1 = "Q1", q2 = "Q2", q3 = "Q3", q4 = "Q4", sem

  var id: String { rawValue }
  static let matriz: [JarvisQuadrante] = [.q1, .q2, .q3, .q4]

  var titulo: String {
    switch self {
    case .q1: return "Faça agora"
    case .q2: return "Agende"
    case .q3: return "Delegue"
    case .q4: return "Depois"
    case .sem: return "Sem classificar"
    }
  }

  var dica: String {
    switch self {
    case .q1: return "Urgente e importante"
    case .q2: return "Importante, não urgente"
    case .q3: return "Urgente, não importante"
    case .q4: return "Nem urgente nem importante"
    case .sem: return "A matriz ainda não passou"
    }
  }

  var cor: Color {
    switch self {
    case .q1: return Color(hex: 0xFFB98A)
    case .q2: return Color(hex: 0xA9BEFF)
    case .q3: return Color(hex: 0xE6DFA0)
    case .q4, .sem: return Color(hex: 0xB7C0BD)
    }
  }

  init(da demanda: JarvisDemanda) {
    self = demanda.quadrante.flatMap(JarvisQuadrante.init(rawValue:)) ?? .sem
  }
}

enum JarvisMatriz {
  /// Abertas por quadrante, só do cliente escolhido; dentro de cada um, vencidas primeiro, depois prazo e id.
  static func agrupar(_ demandas: [JarvisDemanda], cliente: String? = nil) -> [JarvisQuadrante: [JarvisDemanda]] {
    let abertas = demandas.filter {
      $0.situacao != "concluida" && $0.situacao != "cancelada" && (cliente == nil || $0.cliente == cliente)
    }
    var grupos = Dictionary(grouping: abertas, by: JarvisQuadrante.init(da:))
    for (q, itens) in grupos {
      grupos[q] = itens.sorted {
        if $0.venceu != $1.venceu { return $0.venceu }
        let a = $0.prazo ?? "9999", b = $1.prazo ?? "9999"
        return a != b ? a < b : $0.id < $1.id
      }
    }
    return grupos
  }

  static func clientes(_ demandas: [JarvisDemanda]) -> [String] {
    Array(Set(demandas.compactMap(\.cliente))).sorted { $0.localizedCompare($1) == .orderedAscending }
  }

  /// O corpo do POST que arrasta para `q`. Sem classificar não é destino.
  static func corpoMover(para q: JarvisQuadrante) -> [String: Any]? {
    q == .sem ? nil : ["acao": "quadrante", "quadrante": q.rawValue]
  }

  /// "Hoje", "Amanhã", "Ontem", "sex., 20/11" ou "Sem prazo". `prazo` é AAAA-MM-DD.
  static func rotuloPrazo(_ prazo: String?, hoje: Date = Date(), calendario: Calendar = .current) -> String {
    guard let prazo, let dia = dataDoPrazo(prazo, calendario: calendario) else { return "Sem prazo" }
    let delta = calendario.dateComponents([.day], from: calendario.startOfDay(for: hoje), to: dia).day ?? 0
    switch delta {
    case 0: return "Hoje"
    case 1: return "Amanhã"
    case -1: return "Ontem"
    default:
      let f = DateFormatter()
      f.locale = Locale(identifier: "pt_BR")
      f.calendar = calendario
      f.timeZone = calendario.timeZone
      f.dateFormat = "EEE, dd/MM"
      return f.string(from: dia)
    }
  }

  static func dataDoPrazo(_ prazo: String, calendario: Calendar = .current) -> Date? {
    let p = prazo.prefix(10).split(separator: "-").compactMap { Int($0) }
    guard p.count == 3 else { return nil }
    return calendario.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
  }

  static func textoPrazo(_ data: Date, calendario: Calendar = .current) -> String {
    let c = calendario.dateComponents([.year, .month, .day], from: data)
    return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
  }

  static func resumo(_ grupos: [JarvisQuadrante: [JarvisDemanda]]) -> String {
    let todas = grupos.values.flatMap { $0 }
    let vencidas = todas.filter(\.venceu).count
    let base = todas.count == 1 ? "1 aberta" : "\(todas.count) abertas"
    let venc = vencidas == 0 ? "" : (vencidas == 1 ? ", 1 vencida" : ", \(vencidas) vencidas")
    return base + venc + ". Arraste o cartão para mudar o quadrante."
  }
}

// MARK: - Estado da página

@MainActor
final class JarvisTarefasModelo: ObservableObject {
  @Published var demandas: [JarvisDemanda] = []
  @Published var carregando = false
  @Published var erro: String?
  @Published var cliente: String?

  func carregar() async {
    carregando = true
    defer { carregando = false }
    do {
      let dados = try await JarvisCliente.dados("/jarvis/tarefas")
      demandas = try JSONDecoder().decode([JarvisDemanda].self, from: dados)
      erro = nil
    } catch JarvisCliente.Falha.semChave {
      erro = "Falta a chave do Jarvis neste Mac."
    } catch {
      erro = "Não consegui ler as tarefas. Tente de novo."
    }
  }

  /// Muda na tela na hora e manda ao Fly; se falhar, volta e avisa.
  func mudar(_ id: Int, _ corpo: [String: Any], local: (inout JarvisDemanda) -> Void) {
    guard let i = demandas.firstIndex(where: { $0.id == id }) else { return }
    let antes = demandas
    local(&demandas[i])
    let json = JarvisCliente.json(corpo)
    Task {
      do {
        _ = try await JarvisCliente.dados("/jarvis/tarefas/\(id)", metodo: "POST", corpo: json)
      } catch {
        demandas = antes
        erro = "Não gravou a mudança em D\(id). Tente de novo."
      }
    }
  }

  func concluir(_ d: JarvisDemanda) {
    mudar(d.id, ["acao": "concluir"]) { $0.situacao = "concluida" }
  }

  func mover(_ id: Int, para q: JarvisQuadrante) {
    guard let corpo = JarvisMatriz.corpoMover(para: q),
      demandas.first(where: { $0.id == id }).map(JarvisQuadrante.init(da:)) != q
    else { return }
    mudar(id, corpo) { $0.quadrante = q.rawValue }
  }

  func prazo(_ d: JarvisDemanda, _ novo: Date?) {
    let texto = novo.map { JarvisMatriz.textoPrazo($0) }
    mudar(d.id, ["acao": "prazo", "prazo": texto ?? NSNull()]) {
      $0.prazo = texto
      $0.venceu = texto.map { $0 < JarvisMatriz.textoPrazo(Date()) } ?? false
    }
  }
}

// MARK: - Página

struct JarvisTarefasPagina: View {
  @StateObject private var modelo = JarvisTarefasModelo()

  var body: some View {
    let grupos = JarvisMatriz.agrupar(modelo.demandas, cliente: modelo.cliente)
    JarvisPaginaBase(
      titulo: "Tarefas",
      subtitulo: modelo.demandas.isEmpty ? "As demandas do comando, na matriz urgente e importante." : JarvisMatriz.resumo(grupos),
      cor: JarvisHubTema.destaque
    ) {
      HStack(spacing: 8) {
        filtroCliente
        botaoAtualizar
      }
    } content: {
      if let erro = modelo.erro {
        JarvisCartao { Text(erro).font(.system(size: 13.5)).foregroundColor(JarvisHubTema.vermelho) }
      }
      LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
        ForEach(JarvisQuadrante.matriz) { q in
          JarvisQuadranteCaixa(quadrante: q, itens: grupos[q] ?? [], modelo: modelo)
        }
      }
      if let sem = grupos[.sem], !sem.isEmpty {
        JarvisQuadranteCaixa(quadrante: .sem, itens: sem, modelo: modelo)
      }
    }
    .task { await modelo.carregar() }
  }

  private var filtroCliente: some View {
    Menu {
      Button("Todos os clientes") { modelo.cliente = nil }
      Divider()
      ForEach(JarvisMatriz.clientes(modelo.demandas), id: \.self) { c in
        Button(c) { modelo.cliente = c }
      }
    } label: {
      Text(modelo.cliente ?? "Todos os clientes").font(.system(size: 12.5, weight: .medium))
    }
    .menuStyle(.borderlessButton)
    .fixedSize()
    .padding(.horizontal, 12)
    .frame(height: 30)
    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
    .accessibilityIdentifier("jarvis-tarefas-cliente")
  }

  private var botaoAtualizar: some View {
    Button {
      Task { await modelo.carregar() }
    } label: {
      HStack(spacing: 6) {
        if modelo.carregando { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
        Text("Atualizar")
      }
      .font(.system(size: 12.5, weight: .medium))
      .padding(.horizontal, 12)
      .frame(height: 30)
      .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

private struct JarvisQuadranteCaixa: View {
  let quadrante: JarvisQuadrante
  let itens: [JarvisDemanda]
  @ObservedObject var modelo: JarvisTarefasModelo
  @State private var alvo = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline) {
        Text(quadrante.titulo).font(.system(size: 15, weight: .bold)).foregroundColor(quadrante.cor)
        Spacer(minLength: 0)
        Text("\(quadrante.dica), \(itens.count)").font(.system(size: 12)).foregroundColor(JarvisHubTema.secundario)
      }
      if itens.isEmpty {
        Text(alvo ? "Solte aqui" : "Nada aqui.")
          .font(.system(size: 12.5))
          .foregroundColor(JarvisHubTema.apagado)
          .frame(maxWidth: .infinity, minHeight: 40)
      }
      ForEach(itens) { d in
        JarvisCartaoDemanda(demanda: d, modelo: modelo)
          .draggable(String(d.id))
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
    .background(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(alvo ? quadrante.cor.opacity(0.08) : JarvisHubTema.cartao))
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .strokeBorder(alvo ? quadrante.cor.opacity(0.7) : JarvisHubTema.linha, lineWidth: alvo ? 1.5 : 1))
    .dropDestination(for: String.self) { ids, _ in
      guard quadrante != .sem, let id = ids.first.flatMap(Int.init) else { return false }
      modelo.mover(id, para: quadrante)
      return true
    } isTargeted: { alvo = $0 && quadrante != .sem }
    .accessibilityIdentifier("jarvis-quadrante-\(quadrante.rawValue)")
  }
}

private struct JarvisCartaoDemanda: View {
  let demanda: JarvisDemanda
  @ObservedObject var modelo: JarvisTarefasModelo
  @State private var editandoPrazo = false
  @State private var novoPrazo = Date()

  var body: some View {
    HStack(spacing: 10) {
      Button {
        modelo.concluir(demanda)
      } label: {
        RoundedRectangle(cornerRadius: 7)
          .strokeBorder(Color(hex: 0x5E6966), lineWidth: 1.5)
          .frame(width: 22, height: 22)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help("Concluir D\(demanda.id)")
      .accessibilityLabel("Concluir D\(demanda.id)")

      VStack(alignment: .leading, spacing: 2) {
        (Text("D\(demanda.id) ").font(.system(size: 12, design: .monospaced)).foregroundColor(Color(hex: 0x8FA8FF))
          + Text(demanda.titulo).font(.system(size: 13.5, weight: .medium)))
          .lineLimit(2)
        Text(linhaDeBaixo).font(.system(size: 11.5)).foregroundColor(JarvisHubTema.secundario).lineLimit(1)
      }
      .help(demanda.resumo ?? demanda.titulo)
      Spacer(minLength: 0)

      Button {
        novoPrazo = demanda.prazo.flatMap { JarvisMatriz.dataDoPrazo($0) } ?? Date()
        editandoPrazo = true
      } label: {
        Text(JarvisMatriz.rotuloPrazo(demanda.prazo))
          .font(.system(size: 11.5, weight: .medium))
          .foregroundColor(demanda.venceu ? JarvisQuadrante.q1.cor : Color(hex: 0xC9D1CE))
          .padding(.horizontal, 9)
          .frame(height: 26)
          .background(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(hex: 0x39423F)))
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .popover(isPresented: $editandoPrazo, arrowEdge: .bottom) { editorPrazo }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 9)
    .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: 0x212725)))
    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(hex: 0x2E3633)))
  }

  private var linhaDeBaixo: String {
    var partes = [demanda.cliente ?? "Interno"]
    if let r = demanda.responsavel, r != "gabriel" { partes.append(r == "lelia" ? "com Lélia" : "com o time") }
    if demanda.situacao == "esperando_voce" { partes.append("esperando você") }
    if demanda.parada { partes.append("parada há 3 dias") }
    return partes.joined(separator: ", ")
  }

  private var editorPrazo: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Prazo de D\(demanda.id)").font(.system(size: 13, weight: .semibold))
      DatePicker("", selection: $novoPrazo, displayedComponents: .date)
        .datePickerStyle(.graphical)
        .labelsHidden()
        .environment(\.locale, Locale(identifier: "pt_BR"))
      HStack {
        Button("Sem prazo") {
          modelo.prazo(demanda, nil)
          editandoPrazo = false
        }
        Spacer()
        Button("Salvar") {
          modelo.prazo(demanda, novoPrazo)
          editandoPrazo = false
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(14)
    .frame(width: 280)
  }
}
