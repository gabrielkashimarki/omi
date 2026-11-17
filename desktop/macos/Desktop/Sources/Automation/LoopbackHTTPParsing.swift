import Foundation

/// Leitura do `Content-Length` do servidor HTTP de loopback (DesktopAutomationBridge). O corpo é
/// fatiado com `data.index(bodyStart, offsetBy: contentLength)`, que trava com valor negativo e
/// estoura com valor enorme; como a leitura vem antes da autenticação, falha fechado.
enum LoopbackHTTPParsing {
  /// Returns the validated body length, or `nil` if the header value is malformed,
  /// negative, or exceeds `maxBytes` (caller should reject the request).
  static func parseContentLength(_ value: String, maxBytes: Int) -> Int? {
    guard let parsed = Int(value), parsed >= 0, parsed <= maxBytes else {
      return nil
    }
    return parsed
  }
}
