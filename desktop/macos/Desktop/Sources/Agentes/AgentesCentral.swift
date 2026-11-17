//
//  AgentesCentral.swift — as sessões ao vivo do Claude Code e a fila de permissões.
//
//  Portado do Coucou (MIT, © 2026 Louis Raillé, aviso em THIRD_PARTY_COUCOU_LICENSE):
//  `NotchBuddy/Sources/App/HookServer.swift` (fila de aprovação, monitor do fd, tempo de espera)
//  e `NotchBuddy/Sources/App/ApprovalQueue.swift`.
//

import AppKit
import Combine
import Foundation

/// Um pedido de permissão esperando Permitir, Negar ou Sempre.
struct PedidoPermissao: Identifiable, Equatable {
  let id = UUID()
  let sessao: String
  let projeto: String
  let ferramenta: String
  let resumo: String
  let sugestoes: Data?
  let conexao: ConexaoAgente
}

@MainActor
final class AgentesCentral: ObservableObject {
  static let shared = AgentesCentral()

  /// Pasta fixa (não depende do bundle), para os hooks do `~/.claude/settings.json` não mudarem.
  nonisolated static var pasta: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/JarvisAgentes", isDirectory: true)
  }
  nonisolated static var caminhoSocket: String { pasta.appendingPathComponent("agentes.sock").path }
  nonisolated static var caminhoHook: String { pasta.appendingPathComponent("jarvis-hook").path }
  nonisolated static var caminhoLigar: String { pasta.appendingPathComponent("ligar-hooks.sh").path }

  /// Mais que isso na fila, o pedido volta para o terminal.
  static let maxPedidos = 8
  /// O hook espera 118 s; o Jarvis desiste antes e o Claude pergunta no terminal.
  static let esperaPermissao: TimeInterval = 115

  @Published private(set) var quadro = QuadroAgentes()
  @Published private(set) var pedidos: [PedidoPermissao] = []
  /// Chamado a cada evento que muda o humor do mascote (som e reação no notch).
  var aoReagir: ((JarvisEstadoMascote) -> Void)?

  private var servidor: AgentesServidor?
  private var monitores: [UUID: DispatchSourceRead] = [:]

  init() {}

  /// Escreve o hook, abre o socket e mostra o notch. Não mexe no `~/.claude/settings.json`.
  func iniciar(caminhoSocket: String = AgentesCentral.caminhoSocket, mostrarNotch: Bool = true) {
    guard servidor == nil else { return }
    let pasta = URL(fileURLWithPath: caminhoSocket).deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
    try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: pasta.path)
    if caminhoSocket == Self.caminhoSocket {
      AgentesHooks.escreverScripts()
      aoReagir = JarvisSons.reagir
    }
    let servidor = AgentesServidor(caminho: caminhoSocket) { [weak self] evento, conexao in
      Task { @MainActor in self?.receber(evento, conexao: conexao) }
    }
    guard servidor.iniciar() else {
      log("Agentes: não abriu o socket em \(caminhoSocket)")
      return
    }
    self.servidor = servidor
    if mostrarNotch { AgentesNotch.shared.ligar(self) }
  }

  func parar() {
    servidor?.parar()
    servidor = nil
  }

  var estadoMascote: JarvisEstadoMascote {
    let estados = quadro.sessoes.values.map(\.estado)
    if !pedidos.isEmpty || estados.contains(.precisaDeVoce) { return .precisaDeVoce }
    if estados.contains(.erro) { return .erro }
    if estados.contains(.terminou) { return .terminou }
    if estados.contains(.trabalhando) || estados.contains(.pensando) { return .trabalhando }
    return .parado
  }

  func receber(_ evento: EventoAgente, conexao: ConexaoAgente?) {
    let antes = estadoMascote
    quadro.aplicar(evento)
    if let conexao { enfileirar(evento, conexao: conexao) }
    if evento.nome == "Stop" || evento.nome == "StopFailure" {
      // "Terminou" e "erro" duram uns segundos; depois a sessão volta a parada.
      let sessao = evento.sessao
      Task { @MainActor [weak self] in
        try? await Task.sleep(for: .seconds(evento.nome == "Stop" ? 6 : 10))
        self?.voltarAParada(sessao)
      }
    }
    let depois = estadoMascote
    if depois != antes { aoReagir?(depois) }
  }

  func decidir(_ id: UUID, _ decisao: DecisaoPermissao) {
    guard let pedido = remover(id) else { return }
    pedido.conexao.responder(decisao.respostaClaude(sugestoes: pedido.sugestoes))
    var sessao = quadro.sessoes[pedido.sessao]
    sessao?.estado = decisao == .negar ? .parada : .trabalhando
    quadro.sessoes[pedido.sessao] = sessao
  }

  private func voltarAParada(_ sessao: String) {
    guard var s = quadro.sessoes[sessao], s.estado == .terminou || s.estado == .erro else { return }
    s.estado = .parada
    quadro.sessoes[sessao] = s
  }

  private func enfileirar(_ evento: EventoAgente, conexao: ConexaoAgente) {
    guard pedidos.count < Self.maxPedidos else {
      conexao.responder("")
      return
    }
    let pedido = PedidoPermissao(
      sessao: evento.sessao, projeto: evento.projeto, ferramenta: evento.ferramenta ?? "Ferramenta",
      resumo: evento.resumo ?? "", sugestoes: evento.sugestoes, conexao: conexao)
    pedidos.append(pedido)

    // O Claude fechou a conexão (respondido no terminal): o cartão some sem resposta.
    let monitor = DispatchSource.makeReadSource(fileDescriptor: conexao.fd, queue: .main)
    let id = pedido.id
    monitor.setEventHandler { [weak self] in
      MainActor.assumeIsolated {
        guard let self, self.remover(id) != nil else { return }
        close(conexao.fd)
      }
    }
    monitor.resume()
    monitores[id] = monitor

    Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(Self.esperaPermissao))
      guard let self, let pedido = self.remover(id) else { return }
      pedido.conexao.responder("")
    }
  }

  /// Tira da fila e para o monitor; nil se já tinha saído (decidido, expirado ou fechado).
  private func remover(_ id: UUID) -> PedidoPermissao? {
    guard let indice = pedidos.firstIndex(where: { $0.id == id }) else { return nil }
    monitores.removeValue(forKey: id)?.cancel()
    return pedidos.remove(at: indice)
  }
}

/// O hook que o Claude Code chama e o comando que liga os hooks no `~/.claude/settings.json`.
enum AgentesHooks {
  static let eventos: [(nome: String, espera: Int)] = [
    ("SessionStart", 10), ("SessionEnd", 10), ("UserPromptSubmit", 10),
    ("PreToolUse", 10), ("PostToolUse", 10), ("PostToolUseFailure", 10),
    ("Notification", 10), ("Stop", 10), ("StopFailure", 10),
    ("SubagentStart", 10), ("SubagentStop", 10), ("PermissionRequest", 120),
  ]

  /// Sai sempre com 0 e nunca segura o Claude: sem o app aberto, o socket não existe e o hook
  /// termina na hora.
  static let scriptHook = #"""
    #!/bin/sh
    # Hook do Claude Code para o Jarvis (Omi Fork).
    SOCK="$HOME/Library/Application Support/JarvisAgentes/agentes.sock"
    [ -S "$SOCK" ] || exit 0
    T=2
    [ "$1" = "--permissao" ] && T=118
    /usr/bin/curl -s --max-time "$T" --unix-socket "$SOCK" -H 'Content-Type: application/json' \
      -H 'Expect:' --data-binary @- http://jarvis/hook 2>/dev/null
    exit 0
    """#

  /// Liga (ou, com --desligar, desliga) os hooks. Faz backup datado antes; JSON inválido para sem
  /// tocar no arquivo. Só mexe nas entradas do jarvis-hook.
  static var scriptLigar: String {
    let lista = eventos.map { "'\($0.nome)': \($0.espera)" }.joined(separator: ", ")
    return #"""
      #!/bin/sh
      # Liga os hooks do Jarvis no ~/.claude/settings.json. Desligar: ligar-hooks.sh --desligar
      exec /usr/bin/python3 - "$@" <<'PY'
      import json, os, shutil, sys, time
      cfg = os.path.expanduser('~/.claude/settings.json')
      cmd = '"' + os.path.expanduser('~/Library/Application Support/JarvisAgentes/jarvis-hook') + '"'
      desligar = '--desligar' in sys.argv[1:]
      dados = {}
      if os.path.exists(cfg):
          with open(cfg) as f:
              dados = json.load(f)
          copia = cfg + '.antes-jarvis-' + time.strftime('%Y%m%d-%H%M%S')
          shutil.copy2(cfg, copia)
          print('backup:', copia)
      hooks = dados.setdefault('hooks', {})
      for evento, espera in {\#(lista)}.items():
          grupos = [g for g in hooks.get(evento, [])
                    if not any('jarvis-hook' in h.get('command', '') for h in g.get('hooks', []))]
          if not desligar:
              comando = cmd + (' --permissao' if evento == 'PermissionRequest' else '')
              grupos.append({'hooks': [{'type': 'command', 'command': comando, 'timeout': espera}]})
          if grupos:
              hooks[evento] = grupos
          else:
              hooks.pop(evento, None)
      if not hooks:
          dados.pop('hooks', None)
      os.makedirs(os.path.dirname(cfg), exist_ok=True)
      with open(cfg + '.tmp', 'w') as f:
          json.dump(dados, f, indent=2, ensure_ascii=False)
          f.write('\n')
      os.replace(cfg + '.tmp', cfg)
      print('hooks do Jarvis', 'desligados' if desligar else 'ligados', 'em', cfg)
      PY
      """#
  }

  static func escreverScripts() {
    for (caminho, texto) in [
      (AgentesCentral.caminhoHook, scriptHook), (AgentesCentral.caminhoLigar, scriptLigar),
    ] {
      try? (texto + "\n").write(toFile: caminho, atomically: true, encoding: .utf8)
      try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: caminho)
    }
  }

  /// Se o `~/.claude/settings.json` já chama o jarvis-hook (só leitura).
  static var ligados: Bool {
    let cfg = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    guard let texto = try? String(contentsOf: cfg, encoding: .utf8) else { return false }
    return texto.contains("JarvisAgentes/jarvis-hook")
  }
}
