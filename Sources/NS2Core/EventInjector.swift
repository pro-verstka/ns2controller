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
    private var boundsRefreshed = Date.distantPast
    public var dryRun = false

    public var held: (keys: Int, mouse: Int) {
        lock.lock(); defer { lock.unlock() }
        return (heldKeys.count, heldMouse.count)
    }

    public init() {
        bounds = Self.displayBounds()
        source?.localEventsSuppressionInterval = 0
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
            recomputeFlags()
            Log.debug("key down \(code)")
            post(keyCode: code, down: true, modifier: binding.modifierFlag != nil)
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
            recomputeFlags()
            Log.debug("key up \(code)")
            post(keyCode: code, down: false, modifier: binding.modifierFlag != nil)
        case let .mouse(button, number):
            guard heldMouse.remove(number) != nil else { return }
            postMouse(button: button, number: number, down: false)
        case .scroll:
            break
        }
    }

    public func releaseAll() {
        lock.lock(); defer { lock.unlock() }
        let modifiers = heldKeys.filter { KeyBinding.modifierFlags(forKeyCode: $0) != nil }
        for code in heldKeys where !modifiers.contains(code) { post(keyCode: code, down: false, modifier: false) }
        heldKeys = modifiers
        for code in modifiers {
            heldKeys.remove(code)
            recomputeFlags()
            post(keyCode: code, down: false, modifier: true)
        }
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
        var current = CGEvent(source: nil)?.location ?? CGPoint(x: bounds.midX, y: bounds.midY)
        refreshBoundsIfNeeded(around: current)
        let marginX = bounds.width * 0.12
        let marginY = bounds.height * 0.12
        let safe = bounds.insetBy(dx: marginX, dy: marginY)
        if !safe.contains(current) {
            current = CGPoint(x: bounds.midX, y: bounds.midY)
            CGWarpMouseCursorPosition(current)
            Log.debug("cursor recentered")
        }
        let target = CGPoint(x: min(max(current.x + CGFloat(dx), bounds.minX + 2), bounds.maxX - 3),
                             y: min(max(current.y + CGFloat(dy), bounds.minY + 2), bounds.maxY - 3))
        let type: CGEventType = heldMouse.contains(0) ? .leftMouseDragged : (heldMouse.contains(1) ? .rightMouseDragged : .mouseMoved)
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: target, mouseButton: .left) else { return }
        event.setIntegerValueField(.mouseEventDeltaX, value: Int64(dx))
        event.setIntegerValueField(.mouseEventDeltaY, value: Int64(dy))
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }

    private func recomputeFlags() {
        var combined = CGEventFlags()
        for code in heldKeys {
            if let flag = KeyBinding.modifierFlags(forKeyCode: code) { combined.formUnion(flag) }
        }
        flags = combined
    }

    private func post(keyCode: CGKeyCode, down: Bool, modifier: Bool) {
        guard !dryRun, let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else { return }
        if modifier { event.type = .flagsChanged }
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

    private func refreshBoundsIfNeeded(around point: CGPoint) {
        let now = Date()
        guard now.timeIntervalSince(boundsRefreshed) > 0.5 else { return }
        boundsRefreshed = now
        let next = Self.frontmostWindowBounds() ?? Self.displayBounds(containing: point)
        if next != bounds {
            bounds = next
            Log.debug(String(format: "mouse confined to %.0f,%.0f %.0fx%.0f", next.minX, next.minY, next.width, next.height))
        }
    }

    static func frontmostWindowBounds() -> CGRect? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
        let ownPID = Int(getpid())
        for window in windows {
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  (window[kCGWindowOwnerPID as String] as? Int) != ownPID,
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0.1,
                  let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: boundsDictionary),
                  rect.width >= 200, rect.height >= 150 else { continue }
            return rect
        }
        return nil
    }

    private static func displayBounds(containing point: CGPoint) -> CGRect {
        var count: UInt32 = 0
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        guard CGGetActiveDisplayList(16, &displays, &count) == .success, count > 0 else {
            return CGDisplayBounds(CGMainDisplayID())
        }
        let rects = displays.prefix(Int(count)).map(CGDisplayBounds)
        return rects.first { $0.contains(point) } ?? rects[0]
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
