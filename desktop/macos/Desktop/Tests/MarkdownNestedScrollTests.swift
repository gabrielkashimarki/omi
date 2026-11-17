import AppKit
import ObjectiveC
import SwiftUI
import XCTest

@testable import Omi_Computer

@MainActor
final class MarkdownNestedScrollTests: XCTestCase {
  func testWideMarkdownTableMountsAHorizontalScroller() throws {
    let table = """
      | Animal | Class | Superpower | Lifespan | Habitat | Wild Fact |
      | --- | --- | --- | --- | --- | --- |
      | Mantis shrimp | Crustacean | Sees sixteen color receptors | 3–6 years | Tropical ocean floors | Punches with a cavitation bubble |
      """
    let host = NSHostingView(
      rootView: OmiMarkdown(text: table, style: .assistant)
        .frame(width: 360, alignment: .leading)
    )
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 360, height: 400),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    NonintrusiveTestWindow.orderIn(window)
    defer {
      window.orderOut(nil)
      window.contentView = nil
    }

    host.layoutSubtreeIfNeeded()

    let tableScroller = try XCTUnwrap(
      descendantScrollViews(of: host).first(where: { $0.hasHorizontalScroller })
    )
    let documentWidth = try XCTUnwrap(tableScroller.documentView).frame.width
    XCTAssertGreaterThan(documentWidth, tableScroller.contentView.bounds.width)
  }



  private func descendantScrollViews(of view: NSView) -> [NSScrollView] {
    var result = (view as? NSScrollView).map { [$0] } ?? []
    for child in view.subviews {
      result += descendantScrollViews(of: child)
    }
    return result
  }
}

@MainActor
private final class RecordingTranscriptScrollView: NSScrollView {
  private(set) var forwardedWheelEvents = 0

  override func scrollWheel(with event: NSEvent) {
    forwardedWheelEvents += 1
  }
}

private final class NestedScrollFlippedDocumentView: NSView {
  override var isFlipped: Bool { true }
}
