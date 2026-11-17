//
//  AgentesServidor.swift — recebe os hooks do Claude Code num socket Unix local.
//
//  Portado do Coucou (MIT, © 2026 Louis Raillé, aviso em THIRD_PARTY_COUCOU_LICENSE):
//  `NotchBuddy/Sources/App/HookServer.swift` (serverThread, handleClient, sendLine). Diferença: aqui
//  o hook fala HTTP pelo socket (`curl --unix-socket`), então não precisa de relay em Python, e a
//  resposta já sai no formato que o Claude Code lê.
//

import Darwin
import Foundation

/// Uma conexão aberta esperando resposta (o PermissionRequest segura o hook até alguém decidir).
struct ConexaoAgente: Sendable, Hashable {
  let fd: Int32

  /// Responde 200 com o corpo e fecha. Corpo vazio = o hook não imprime nada e o Claude segue o
  /// fluxo dele (pergunta no terminal).
  func responder(_ corpo: String) {
    let bytes = Array(corpo.utf8)
    let cabecalho =
      "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(bytes.count)\r\nConnection: close\r\n\r\n"
    enviar(Array(cabecalho.utf8) + bytes)
    close(fd)
  }

  private func enviar(_ bytes: [UInt8]) {
    bytes.withUnsafeBytes { buffer in
      var enviados = 0
      while enviados < buffer.count {
        let n = Darwin.send(fd, buffer.baseAddress! + enviados, buffer.count - enviados, 0)
        if n <= 0 { break }
        enviados += n
      }
    }
  }
}

final class AgentesServidor: @unchecked Sendable {
  static let maxCorpo = 1_000_000
  static let maxConexoes = 64

  let caminho: String
  /// Chamado fora da main thread com o evento lido e a conexão (só PermissionRequest fica aberta).
  private let aoReceber: @Sendable (EventoAgente, ConexaoAgente?) -> Void
  private let trava = NSLock()
  private var conexoes = 0
  private var fdServidor: Int32 = -1

  init(caminho: String, aoReceber: @escaping @Sendable (EventoAgente, ConexaoAgente?) -> Void) {
    self.caminho = caminho
    self.aoReceber = aoReceber
  }

  /// Abre o socket (só o dono lê e escreve) e começa a aceitar conexões. Falso se não deu.
  @discardableResult
  func iniciar() -> Bool {
    let limite = MemoryLayout<sockaddr_un>.size - MemoryLayout<sa_family_t>.size - 1
    guard caminho.utf8.count <= limite else { return false }
    unlink(caminho)

    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return false }
    var endereco = sockaddr_un()
    endereco.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(caminho.utf8CString)
    withUnsafeMutableBytes(of: &endereco.sun_path) { raw in
      for (i, c) in bytes.enumerated() where i < raw.count { raw[i] = UInt8(bitPattern: c) }
    }
    let ligou = withUnsafePointer(to: &endereco) { ptr in
      ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    guard ligou == 0 else {
      close(fd)
      return false
    }
    chmod(caminho, 0o600)
    guard Darwin.listen(fd, 32) == 0 else {
      close(fd)
      return false
    }
    fdServidor = fd
    Thread.detachNewThread { self.aceitar(fd) }
    return true
  }

  func parar() {
    guard fdServidor >= 0 else { return }
    close(fdServidor)
    fdServidor = -1
    unlink(caminho)
  }

  private func aceitar(_ fd: Int32) {
    while true {
      let cliente = Darwin.accept(fd, nil, nil)
      guard cliente >= 0 else {
        let erro = errno
        if erro == EBADF || erro == EINVAL || erro == ENOTSOCK { return }
        if erro != EINTR && erro != ECONNABORTED { usleep(100_000) }
        continue
      }
      // Só o mesmo usuário fala com o socket.
      var euid: uid_t = 0
      var egid: gid_t = 0
      guard getpeereid(cliente, &euid, &egid) == 0, euid == getuid() else {
        close(cliente)
        continue
      }
      trava.lock()
      let cheio = conexoes >= Self.maxConexoes
      if !cheio { conexoes += 1 }
      trava.unlock()
      guard !cheio else {
        close(cliente)
        continue
      }
      Thread.detachNewThread { self.atender(cliente) }
    }
  }

  private func atender(_ fd: Int32) {
    defer {
      trava.lock()
      conexoes -= 1
      trava.unlock()
    }
    var espera = timeval(tv_sec: 5, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &espera, socklen_t(MemoryLayout<timeval>.size))
    let conexao = ConexaoAgente(fd: fd)

    guard let corpo = Self.lerCorpo(fd), let evento = EventoAgente.ler(corpo) else {
      conexao.responder("")
      return
    }
    if evento.nome == "PermissionRequest", evento.ferramenta != "AskUserQuestion" {
      // Fica aberta: quem fecha é a decisão, o tempo esgotado ou o Claude respondendo no terminal.
      aoReceber(evento, conexao)
    } else {
      conexao.responder("")
      aoReceber(evento, nil)
    }
  }

  /// Lê uma requisição HTTP até o fim do corpo (Content-Length).
  static func lerCorpo(_ fd: Int32) -> Data? {
    var dados = Data()
    var buffer = [UInt8](repeating: 0, count: 8192)
    let separador = Data("\r\n\r\n".utf8)
    var tamanho: Int?
    var inicioCorpo = 0
    while true {
      if let tamanho, dados.count - inicioCorpo >= tamanho {
        return dados.subdata(in: inicioCorpo..<(inicioCorpo + tamanho))
      }
      let n = recv(fd, &buffer, buffer.count, 0)
      if n <= 0 { return nil }
      dados.append(contentsOf: buffer[0..<n])
      if dados.count > maxCorpo + 16_384 { return nil }
      if tamanho == nil, let fim = dados.range(of: separador) {
        let cabecalho = String(decoding: dados[..<fim.lowerBound], as: UTF8.self).lowercased()
        let linha = cabecalho.split(separator: "\r\n").first { $0.hasPrefix("content-length:") }
        guard let linha, let valor = Int(linha.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)),
          valor <= maxCorpo
        else { return nil }
        tamanho = valor
        inicioCorpo = fim.upperBound
      }
    }
  }
}
