// E2E-only input driver. AXPress does not open SwiftUI's window-style
// MenuBarExtra in our macOS 27 test session. A mouse event with clickState == 0
// also does nothing; send a complete single click at the AX-reported position.
import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 3,
      let x = Double(CommandLine.arguments[1]),
      let y = Double(CommandLine.arguments[2]),
      x.isFinite, y.isFinite else {
    fputs("Usage: click_status_item <screen-x> <screen-y>\n", stderr)
    exit(1)
}

let point = CGPoint(x: x, y: y)
for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
    guard let event = CGEvent(mouseEventSource: nil, mouseType: type,
                              mouseCursorPosition: point, mouseButton: .left) else {
        fputs("Unable to create status-item click\n", stderr)
        exit(1)
    }
    event.flags = []
    event.setIntegerValueField(.mouseEventClickState, value: 1)
    event.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.1)
}
