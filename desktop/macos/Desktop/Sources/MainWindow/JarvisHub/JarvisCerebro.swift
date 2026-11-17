//
//  JarvisCerebro.swift — a página Cérebro: as asserções do Cérebro Operacional e as perguntas para o Gabriel.
//
//  Lê `GET /jarvis/cerebro?lista=ativas|rascunho|contestadas|perguntas&cliente=&q=` (RPC jarvis_cerebro no Fly).
//  Responder uma pergunta grava pelo `POST /api/cerebro/registrar` (nasce rascunho) e fecha a pergunta; aprovar e
//  recusar rascunho passam pela promoção do autoblogger (`/api/cerebro/promover`).
//

import SwiftUI

// MARK: - Dados e montagem (puro, testado)

struct JarvisAssercao: Decodable, Identifiable, Equatable, Sendable {
  let id: String
  let enunciado: String
  let estado: String
  let camada: String?
  let tipo: String?
  let cliente: String?
  let fonte_trecho: String?
  let motivo: String?
  let motivo_tipo: String?
}

struct JarvisPergunta: Decodable, Identifiable, Equatable, Sendable {
  let id: String
  let pergunta: String
  let enunciado: String?
  let cliente: String?
  let criado_em: String?
}

struct JarvisClienteCerebro: Decodable, Identifiable, Equatable, Sendable {
  let id: String
  let nome: String
}

enum JarvisCerebroLista: String, CaseIterable, Identifiable {
  case ativas, rascunho, contestadas

  var id: String { rawValue }

  var titulo: String {
    switch self {
    case .ativas: return "Ativas"
    case .rascunho: return "Rascunho"
    case .contestadas: return "Contestadas e recusadas"
    }
  }
}

enum JarvisCerebroMontagem {
  struct Resposta<Item: Decodable>: Decodable {
    let itens: [Item]
    let clientes: [JarvisClienteCerebro]
  }

  /// O selo de estado: "recusada" é a asserção arquivada (morta na promoção).
  static func selo(_ estado: String) -> (texto: String, cor: Color) {
    switch estado {
    case "ativa": return ("Ativa", Color(hex: 0x7FE0B5))
    case "rascunho": return ("Rascunho", Color(hex: 0xB9C8FF))
    case "contestada": return ("Contestada", Color(hex: 0xF3D38A))
    case "arquivada": return ("Recusada", Color(hex: 0xFF9D9D))
    default: return (estado.capitalized, JarvisHubTema.secundario)
    }
  }

  /// Contestada e recusada sempre mostram o porquê; sem conflito gravado, diz isso em vez de esconder.
  static func motivo(_ a: JarvisAssercao) -> String? {
    guard a.estado == "contestada" || a.estado == "arquivada" else { return nil }
    let rotulo = selo(a.estado).texto
    let tipo: String? = {
      switch a.motivo_tipo {
      case "contradicao": return "contradiz outra asserção"
      case "duplicata": return "repete outra asserção"
      case "obsolescencia": return "ficou velha"
      case "ambiguidade": return "ficou ambígua"
      default: return nil
      }
    }()
    guard let m = a.motivo?.trimmingCharacters(in: .whitespacesAndNewlines), !m.isEmpty else {
      return "\(rotulo): " + (tipo ?? "sem motivo registrado") + "."
    }
    return "\(rotulo)" + (tipo.map { " (\($0))" } ?? "") + ": \(m)"
  }

  /// "Regra, L1 política" a partir do tipo e da camada.
  static func origem(_ a: JarvisAssercao) -> String {
    let tipo = a.tipo.map { $0.prefix(1).uppercased() + $0.dropFirst() }
    let camada: String? = {
      switch a.camada {
      case "L0_identidade": return "identidade"
      case "L1_politica": return "política"
      case "L2_procedimento": return "procedimento"
      case "L3_estado": return "estado"
      default: return nil
      }
    }()
    return [tipo, camada].compactMap { $0 }.joined(separator: ", ")
  }

  static func caminho(_ lista: String, cliente: String?, busca: String) -> String {
    // URLQueryItem não escapa & e =: uma busca com "&" viraria outro parâmetro
    var permitido = CharacterSet.urlQueryAllowed
    permitido.remove(charactersIn: "&=+?#")
    func e(_ v: String) -> String { v.addingPercentEncoding(withAllowedCharacters: permitido) ?? "" }
    var c = "/jarvis/cerebro?lista=\(e(lista))"
    if let cliente { c += "&cliente=\(e(cliente))" }
    let b = busca.trimmingCharacters(in: .whitespacesAndNewlines)
    if !b.isEmpty { c += "&q=\(e(b))" }
    return c
  }
}

// MARK: - Estado da página

@MainActor
final class JarvisCerebroModelo: ObservableObject {
  @Published var lista: JarvisCerebroLista = .ativas
  @Published var cliente: JarvisClienteCerebro?
  @Published var busca = ""
  @Published var itens: [JarvisAssercao] = []
  @Published var perguntas: [JarvisPergunta] = []
  @Published var clientes: [JarvisClienteCerebro] = []
  @Published var carregando = false
  @Published var erro: String?
  @Published var aviso: String?

  func carregar() async {
    carregando = true
    defer { carregando = false }
    do {
      async let a = JarvisCliente.dados(
        JarvisCerebroMontagem.caminho(lista.rawValue, cliente: cliente?.id, busca: busca))
      async let p = JarvisCliente.dados(
        JarvisCerebroMontagem.caminho("perguntas", cliente: cliente?.id, busca: busca))
      let ra = try JSONDecoder().decode(JarvisCerebroMontagem.Resposta<JarvisAssercao>.self, from: try await a)
      let rp = try JSONDecoder().decode(JarvisCerebroMontagem.Resposta<JarvisPergunta>.self, from: try await p)
      itens = ra.itens
      perguntas = rp.itens
      clientes = ra.clientes
      erro = nil
    } catch JarvisCliente.Falha.semChave {
      erro = "Falta a chave do Jarvis neste Mac."
    } catch {
      erro = "Não consegui ler o Cérebro. Tente de novo."
    }
  }

  func responder(_ p: JarvisPergunta, _ texto: String) async -> Bool {
    do {
      _ = try await JarvisCliente.dados(
        "/jarvis/cerebro/resposta", metodo: "POST",
        corpo: JarvisCliente.json(["pergunta_id": p.id, "resposta": texto]))
      perguntas.removeAll { $0.id == p.id }
      aviso = "Resposta gravada no Cérebro como rascunho."
      return true
    } catch {
      erro = "A resposta não foi gravada. Tente de novo."
      return false
    }
  }

  func decidir(_ a: JarvisAssercao, aprovar: Bool) async {
    do {
      _ = try await JarvisCliente.dados(
        "/jarvis/cerebro/\(a.id)/estado", metodo: "POST",
        corpo: JarvisCliente.json(["decisao": aprovar ? "aprovar" : "recusar"]))
      itens.removeAll { $0.id == a.id }
      aviso = aprovar ? "Asserção aprovada: agora é ativa." : "Asserção recusada."
    } catch {
      erro = "Não consegui \(aprovar ? "aprovar" : "recusar") a asserção."
    }
  }
}

// MARK: - Página

struct JarvisCerebroPagina: View {
  @StateObject private var modelo = JarvisCerebroModelo()

  var body: some View {
    JarvisPaginaBase(
      titulo: "Cérebro",
      subtitulo: "O que virou verdade, o que é rascunho, o que foi contestado e por quê, e o que falta você responder.",
      cor: Color(hex: 0x7FD6B4)
    ) {
      HStack(spacing: 8) {
        filtroCliente
        TextField("Buscar", text: $modelo.busca)
          .textFieldStyle(.plain)
          .font(.system(size: 12.5))
          .padding(.horizontal, 10)
          .frame(width: 200, height: 30)
          .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
          .onSubmit { Task { await modelo.carregar() } }
          .accessibilityIdentifier("jarvis-cerebro-busca")
        if modelo.carregando { ProgressView().controlSize(.small) }
      }
    } content: {
      if let erro = modelo.erro {
        JarvisCartao { Text(erro).font(.system(size: 13.5)).foregroundColor(JarvisHubTema.vermelho) }
      }
      if let aviso = modelo.aviso {
        Text(aviso).font(.system(size: 12.5)).foregroundColor(JarvisHubTema.verde)
      }
      HStack(alignment: .top, spacing: 18) {
        VStack(alignment: .leading, spacing: 10) {
          HStack(spacing: 6) {
            ForEach(JarvisCerebroLista.allCases) { l in
              chip(l.titulo, ativo: modelo.lista == l) {
                modelo.lista = l
                Task { await modelo.carregar() }
              }
            }
          }
          if modelo.itens.isEmpty, !modelo.carregando {
            JarvisCartao { Text("Nada nesta lista.").foregroundColor(JarvisHubTema.secundario) }
          }
          ForEach(modelo.itens) { a in JarvisLinhaAssercao(assercao: a, modelo: modelo) }
          if modelo.itens.count >= 200 {
            Text("Mostrando as 200 mais recentes. Filtre por cliente ou busque para ver as outras.")
              .font(.system(size: 12)).foregroundColor(JarvisHubTema.apagado)
          }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .layoutPriority(1.65)

        VStack(alignment: .leading, spacing: 12) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Perguntas para você").font(.system(size: 16, weight: .bold))
            Text("O destilador não soube decidir. Sua resposta entra no Cérebro e segue o ciclo normal.")
              .font(.system(size: 12)).foregroundColor(JarvisHubTema.secundario)
          }
          if modelo.perguntas.isEmpty, !modelo.carregando {
            Text("Nenhuma pergunta aberta.").font(.system(size: 12.5)).foregroundColor(JarvisHubTema.apagado)
          }
          ForEach(modelo.perguntas.prefix(40)) { p in JarvisCaixaPergunta(pergunta: p, modelo: modelo) }
          if modelo.perguntas.count > 40 {
            Text("Mais \(modelo.perguntas.count - 40) perguntas. Filtre por cliente para ver as outras.")
              .font(.system(size: 12)).foregroundColor(JarvisHubTema.apagado)
          }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0x171D1B)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color(hex: 0x2C4A40)))
      }
    }
    .task { await modelo.carregar() }
  }

  private var filtroCliente: some View {
    Menu {
      Button("Todos os clientes") {
        modelo.cliente = nil
        Task { await modelo.carregar() }
      }
      Divider()
      ForEach(modelo.clientes) { c in
        Button(c.nome) {
          modelo.cliente = c
          Task { await modelo.carregar() }
        }
      }
    } label: {
      Text(modelo.cliente?.nome ?? "Todos os clientes").font(.system(size: 12.5, weight: .medium))
    }
    .menuStyle(.borderlessButton)
    .fixedSize()
    .padding(.horizontal, 12)
    .frame(height: 30)
    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
    .accessibilityIdentifier("jarvis-cerebro-cliente")
  }

  private func chip(_ texto: String, ativo: Bool, acao: @escaping () -> Void) -> some View {
    Button(action: acao) {
      Text(texto)
        .font(.system(size: 13, weight: ativo ? .semibold : .regular))
        .foregroundColor(ativo ? JarvisHubTema.texto : Color(hex: 0xC9D1CE))
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 8).fill(ativo ? Color(hex: 0x26302D) : Color(hex: 0x161A19)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(ativo ? Color(hex: 0x3D4A46) : Color(hex: 0x2E3633)))
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

private struct JarvisLinhaAssercao: View {
  let assercao: JarvisAssercao
  @ObservedObject var modelo: JarvisCerebroModelo

  var body: some View {
    let selo = JarvisCerebroMontagem.selo(assercao.estado)
    HStack(alignment: .top, spacing: 12) {
      Text(assercao.cliente ?? "—")
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(Color(hex: 0xCFE9DE))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0x26302D)))
        .lineLimit(1)
      VStack(alignment: .leading, spacing: 4) {
        Text(assercao.enunciado).font(.system(size: 13.5)).fixedSize(horizontal: false, vertical: true)
          .textSelection(.enabled)
        let origem = JarvisCerebroMontagem.origem(assercao)
        let trecho = assercao.fonte_trecho.map { "\"\($0.prefix(160))\"" }
        Text([origem.isEmpty ? nil : origem, trecho].compactMap { $0 }.joined(separator: ". "))
          .font(.system(size: 12)).foregroundColor(JarvisHubTema.secundario).lineLimit(2)
        if let m = JarvisCerebroMontagem.motivo(assercao) {
          Text(m)
            .font(.system(size: 12))
            .foregroundColor(Color(hex: 0xF2C9A8))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0x2A1E16)))
            .fixedSize(horizontal: false, vertical: true)
        }
        if assercao.estado == "rascunho" {
          HStack(spacing: 8) {
            botao("Aprovar", cor: JarvisHubTema.verde) { Task { await modelo.decidir(assercao, aprovar: true) } }
            botao("Recusar", cor: JarvisHubTema.vermelho) { Task { await modelo.decidir(assercao, aprovar: false) } }
          }
          .padding(.top, 2)
        }
      }
      Spacer(minLength: 0)
      Text(selo.texto)
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(selo.cor)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(selo.cor.opacity(0.14)))
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: 0x202624)))
    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(hex: 0x2C3431)))
  }

  private func botao(_ titulo: String, cor: Color, acao: @escaping () -> Void) -> some View {
    Button(action: acao) {
      Text(titulo)
        .font(.system(size: 12, weight: .semibold))
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 7).fill(cor.opacity(0.18)))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(cor.opacity(0.45)))
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

private struct JarvisCaixaPergunta: View {
  let pergunta: JarvisPergunta
  @ObservedObject var modelo: JarvisCerebroModelo
  @State private var resposta = ""
  @State private var enviando = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(pergunta.cliente ?? "—").font(.system(size: 12)).foregroundColor(JarvisHubTema.secundario)
      Text(pergunta.pergunta).font(.system(size: 13.5)).fixedSize(horizontal: false, vertical: true)
      if let e = pergunta.enunciado {
        Text("Sobre: \(e)").font(.system(size: 11.5)).foregroundColor(JarvisHubTema.apagado).lineLimit(2)
      }
      HStack(spacing: 8) {
        TextField("Digite a resposta", text: $resposta)
          .textFieldStyle(.plain)
          .font(.system(size: 13))
          .padding(.horizontal, 10)
          .frame(height: 32)
          .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x121615)))
          .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(hex: 0x39423F)))
          .onSubmit(enviar)
        Button(action: enviar) {
          Text(enviando ? "Gravando…" : "Responder")
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(Color(hex: 0xDDF5EA))
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x1F3A30)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(hex: 0x2E5A4A)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(enviando || resposta.trimmingCharacters(in: .whitespaces).count < 2)
      }
    }
    .padding(12)
    .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: 0x1F2624)))
    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(hex: 0x2E3633)))
  }

  private func enviar() {
    let t = resposta.trimmingCharacters(in: .whitespacesAndNewlines)
    guard t.count >= 2, !enviando else { return }
    enviando = true
    Task {
      if await modelo.responder(pergunta, t) { resposta = "" }
      enviando = false
    }
  }
}
