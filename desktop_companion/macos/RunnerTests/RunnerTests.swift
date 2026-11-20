import Cocoa
import FlutterMacOS
import XCTest
@testable import LumiaKey

class RunnerTests: XCTestCase {
  func testTestFlightPostingDoesNotRequireAXTrust() {
    XCTAssertTrue(MacInputPermissions.canPostPointer(
      testFlight: true, eventPosting: true, accessibility: false))
    XCTAssertFalse(MacInputPermissions.canPostPointer(
      testFlight: true, eventPosting: false, accessibility: true))
    XCTAssertFalse(MacInputPermissions.canPostPointer(
      testFlight: false, eventPosting: true, accessibility: false))
    XCTAssertTrue(MacInputPermissions.canPostPointer(
      testFlight: false, eventPosting: true, accessibility: true))
  }

  func testShortcutChordUsesActiveLayoutAndRejectsMultipleKeys() throws {
    let translate: (String) -> (code: CGKeyCode, flags: CGEventFlags)? = {
      $0 == "z" ? (6, .maskAlternate) : nil
    }
    let chord = try XCTUnwrap(MacShortcutChord.parse(["COMMAND", "Z"], characterKey: translate))
    XCTAssertEqual(chord.keyCode, 6)
    XCTAssertEqual(chord.flags, [.maskCommand, .maskAlternate])
    XCTAssertEqual(MacShortcutChord.parse(["LEFT"], characterKey: translate)?.keyCode, 123)
    XCTAssertNil(MacShortcutChord.parse(["COMMAND"], characterKey: translate))
    XCTAssertNil(MacShortcutChord.parse(["COMMAND", "Z", "LEFT"], characterKey: translate))
    XCTAssertNil(MacShortcutChord.parse(["COMMAND", "!" ], characterKey: translate))
  }

  func testGuardRecognizesChatGPTWithTheCurrentAndHistoricalBundleIdentifiers() {
    XCTAssertTrue(MainFlutterWindow.matchesShortcutApp(
      "chatgpt", bundleId: "com.openai.codex", name: "ChatGPT"))
    XCTAssertTrue(MainFlutterWindow.matchesShortcutApp("chatgpt", bundleId: "com.openai.chat"))
    XCTAssertTrue(MainFlutterWindow.matchesShortcutApp("chatgpt", bundleId: "com.openai.chatgpt"))
    XCTAssertFalse(MainFlutterWindow.matchesShortcutApp(
      "chatgpt", bundleId: "com.openai.codex", name: "Codex"))
    XCTAssertFalse(MainFlutterWindow.matchesShortcutApp("chatgpt", bundleId: "com.fake.chatgpt"))
    XCTAssertFalse(MainFlutterWindow.matchesShortcutApp("unknown", bundleId: "com.openai.codex"))
  }

  func testMovementCGEventUsesAbsoluteDestinationAndAccumulatesBatch() throws {
    let displays = [CGRect(x: 0, y: 0, width: 100, height: 100)]
    var location = CGPoint(x: 20, y: 30)
    let first = try XCTUnwrap(
      PointerEventFactory.move(from: location, deltaX: 7, deltaY: -4,
                               displayBounds: displays)
    )
    XCTAssertEqual(first.event.location, CGPoint(x: 27, y: 26))
    location = first.location

    let second = try XCTUnwrap(
      PointerEventFactory.move(from: location, deltaX: -2, deltaY: 8,
                               displayBounds: displays)
    )
    XCTAssertEqual(second.event.location, CGPoint(x: 25, y: 34))
    XCTAssertEqual(second.location, CGPoint(x: 25, y: 34))
    XCTAssertEqual(second.event.getIntegerValueField(.mouseEventDeltaX), -2)
    XCTAssertEqual(second.event.getIntegerValueField(.mouseEventDeltaY), 8)
  }

  func testMovementClampsToNearestActiveMonitorWithoutAssumingPrimary() throws {
    let displays = [
      CGRect(x: -100, y: 0, width: 100, height: 100),
      CGRect(x: 0, y: 0, width: 100, height: 100),
    ]
    let movement = try XCTUnwrap(
      PointerEventFactory.move(from: CGPoint(x: 98, y: 50), deltaX: 10,
                               deltaY: 0, displayBounds: displays)
    )
    XCTAssertEqual(movement.event.location.x, CGFloat(100).nextDown)
    XCTAssertEqual(movement.event.location.y, 50)
    XCTAssertTrue(displays.contains { $0.contains(movement.location) })
  }
}
