import Foundation
import XCTest

@testable import Omi_Computer

final class DiarioVaultTests: XCTestCase {
  private let nota = """
    ---
    data: 2026-11-14
    tipo: diario
    ---

    # 14/11/2026, sábado
    <!-- diario:gerado inicio -->
    ## Em uma linha
    Sábado tranquilo. Um lead novo chegou.

    ## Conversas
    **Fazenda Monduá (grupo)**
    - 08:11, aviso de lead novo [[Caroline]].

    ## Omi
    - [ ] Responder a Caroline
    - [x] Conferir extrato

    ## Pontas soltas
    - Lead sem retorno.
    <!-- diario:gerado fim -->
    """

  func testNotaViraRegistro() throws {
    let r = try XCTUnwrap(DiarioVault.registro(data: "2026-11-14", markdown: nota))
    XCTAssertEqual(r.id, "vault:2026-11-14")
    XCTAssertEqual(r.headline, "Sábado tranquilo")
    XCTAssertEqual(r.overview, "Sábado tranquilo. Um lead novo chegou.")
    XCTAssertEqual(r.highlights?.map(\.topic), ["Conversas"])
    XCTAssertEqual(r.highlights?.first?.summary, "Fazenda Monduá (grupo)\n• 08:11, aviso de lead novo Caroline.")
    XCTAssertEqual(r.actionItems?.map(\.description), ["Responder a Caroline", "Conferir extrato"])
    XCTAssertEqual(r.actionItems?.map(\.completed), [false, true])
    XCTAssertEqual(r.unresolvedQuestions?.map(\.question), ["Lead sem retorno."])
  }

  func testVaultGanhaDaNuvemNoMesmoDia() throws {
    let pasta = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: pasta) }
    try nota.write(to: pasta.appendingPathComponent("2026-11-14.md"), atomically: true, encoding: .utf8)
    try "rascunho".write(to: pasta.appendingPathComponent("ideias.md"), atomically: true, encoding: .utf8)
    let nuvem = [
      DailySummaryRecord(id: "ds_15", date: "2026-11-15", headline: "Cloud", overview: nil),
      DailySummaryRecord(id: "ds_14", date: "2026-11-14", headline: "Cloud", overview: nil),
    ]
    let r = DiarioVault.mesclar(nuvem: nuvem, limite: 14, pasta: pasta)
    XCTAssertEqual(r.map(\.id), ["ds_15", "vault:2026-11-14"])
  }
}
