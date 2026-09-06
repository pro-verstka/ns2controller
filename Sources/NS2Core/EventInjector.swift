import Foundation
import CoreGraphics
import ApplicationServices

public final class EventInjector: @unchecked Sendable {
    private let lock = NSLock()
    private let source = CGEventSource(stateID: .combinedSessionState)
    private var heldKeys: Set<CGKeyCode> = []
    private var heldMouse: Set<Int64> = []
    private var flags: CGEventFlags = []
    private var bounds: CGRect = .zero
    public var dryRun = false

    public var held: (keys: Int, mouse: Int) {
        lock.lock(); defer { lock.unlock() }
        return (heldKeys.count, heldMouse.count)
    }

    public init() {
        bounds = Self.displayBounds()
    }

    public static func isAccessibilityTrusted(prompt: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = [url.absoluteString]
        try? task.run()
    }

    public func press(_ binding: KeyBinding) {
        lock.lock(); defer { lock.unlock() }
        switch binding {
        case let .key(code):
            guard heldKeys.insert(code).inserted else { return }
            if let flag = binding.modifierFlag { flags.insert(flag) }
            Log.debug("key down \(code)")
            post(keyCode: code, down: true)
        case let .mouse(button, number):
            guard heldMouse.insert(number).inserted else { return }
            Log.debug("mouse button \(number) down")
            postMouse(button: button, number: number, down: true)
        case let .scroll(lines):
            postScroll(lines)
        }
    }

    public func release(_ binding: KeyBinding) {
        lock.lock(); defer { lock.unlock() }
        switch binding {
        case let .key(code):
            guard heldKeys.remove(code) != nil else { return }
            if let flag = binding.modifierFlag { flags.remove(flag) }
            Log.debug("key up \(code)")
            post(keyCode: code, down: false)
        case let .mouse(button, number):
            guard heldMouse.remove(number) != nil else { return }
            postMouse(button: button, number: number, down: false)
        case .scroll:
            break
        }
    }

    public func releaseAll() {
        lock.lock(); defer { lock.unlock() }
        for code in heldKeys { post(keyCode: code, down: false) }
        heldKeys.removeAll()
        for number in heldMouse {
            let button: CGMouseButton = number == 0 ? .left : (number == 1 ? .right : .center)
            postMouse(button: button, number: number, down: false)
        }
        heldMouse.removeAll()
        flags = []
    }

    public func moveMouse(dx: Int, dy: Int) {
        guard dx != 0 || dy != 0 else { return }
        lock.lock(); defer { lock.unlock() }
        guard !dryRun else { return }
        let current = CGEvent(source: nil)?.location ?? CGPoint(x: bounds.midX, y: bounds.midY)
        let target = CGPoint(x: min(max(current.x + CGFloat(dx), bounds.minX), bounds.maxX - 1),
                             y: min(max(current.y + CGFloat(dy), bounds.minY), bounds.maxY - 1))
        let type: CGEventType = heldMouse.contains(0) ? .leftMouseDragged : (heldMouse.contains(1) ? .rightMouseDragged : .mouseMoved)
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: target, mouseButton: .left) else { return }
        event.setIntegerValueField(.mouseEventDeltaX, value: Int64(dx))
        event.setIntegerValueField(.mouseEventDeltaY, value: Int64(dy))
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }

    private func post(keyCode: CGKeyCode, down: Bool) {
        guard !dryRun, let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else { return }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }

    private func postMouse(button: CGMouseButton, number: Int64, down: Bool) {
        guard !dryRun else { return }
        let position = CGEvent(source: nil)?.location ?? CGPoint(x: bounds.midX, y: bounds.midY)
        let type: CGEventType
        switch number {
        case 0: type = down ? .leftMouseDown : .leftMouseUp
        case 1: type = down ? .rightMouseDown : .rightMouseUp
        default: type = down ? .otherMouseDown : .otherMouseUp
        }
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: position, mouseButton: button) else { return }
        if number > 1 { event.setIntegerValueField(.mouseEventButtonNumber, value: number) }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }

    private func postScroll(_ lines: Int32) {
        guard !dryRun, let event = CGEvent(scrollWheelEvent2Source: source, units: .line, wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0) else { return }
        event.post(tap: .cghidEventTap)
    }

    private static func displayBounds() -> CGRect {
        var count: UInt32 = 0
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        guard CGGetActiveDisplayList(16, &displays, &count) == .success, count > 0 else {
            return CGDisplayBounds(CGMainDisplayID())
        }
        return displays.prefix(Int(count)).map(CGDisplayBounds).reduce(CGRect.null) { $0.union($1) }
    }
}
