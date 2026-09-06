import Foundation

public struct DirectionHysteresis: Sendable {
    public var threshold: Double
    public private(set) var active = false

    public init(threshold: Double) {
        self.threshold = threshold
    }

    public mutating func update(_ value: Double) -> Bool? {
        let limit = active ? threshold * 0.8 : threshold
        let next = value > limit
        guard next != active else { return nil }
        active = next
        return next
    }
}

public struct MouseAccumulator: Sendable {
    private var fractionX = 0.0
    private var fractionY = 0.0

    public init() {}

    public mutating func add(dx: Double, dy: Double) -> (Int, Int) {
        fractionX += dx
        fractionY += dy
        let wholeX = fractionX.rounded(.towardZero)
        let wholeY = fractionY.rounded(.towardZero)
        fractionX -= wholeX
        fractionY -= wholeY
        return (Int(wholeX), Int(wholeY))
    }
}

public final class KBMBridge: @unchecked Sendable {
    public let profile: ResolvedProfile
    public let calibration: (left: StickCalibration, right: StickCalibration)
    private let injector: EventInjector
    private let lock = NSLock()
    private var previous = ControllerState.idle
    private var lastTime: TimeInterval?
    private var leftDirections: [DirectionHysteresis]
    private var rightDirections: [DirectionHysteresis]
    private var leftMouse = MouseAccumulator()
    private var rightMouse = MouseAccumulator()
    private var comboHeldSince: TimeInterval?
    private var comboLatched = false
    public private(set) var paused = false
    public var onPauseChange: (@Sendable (Bool) -> Void)?

    public init(profile: ResolvedProfile, calibration: (left: StickCalibration, right: StickCalibration), injector: EventInjector) {
        self.profile = profile
        self.calibration = calibration
        self.injector = injector
        leftDirections = Self.directions(for: profile.left)
        rightDirections = Self.directions(for: profile.right)
    }

    private static func directions(for stick: ResolvedStick) -> [DirectionHysteresis] {
        if case let .keys(threshold, _, _, _, _) = stick.mode {
            return Array(repeating: DirectionHysteresis(threshold: threshold), count: 4)
        }
        return []
    }

    public func handle(_ state: ControllerState, at time: TimeInterval = Date().timeIntervalSinceReferenceDate) {
        lock.lock(); defer { lock.unlock() }
        let dt = min(0.05, max(0.001, time - (lastTime ?? time - 0.004)))
        lastTime = time
        updatePauseCombo(state, time: time)
        guard !paused else { previous = state; return }
        updateButtons(state)
        leftDirections = updateStick(profile.left, raw: state.leftRaw, calibration: calibration.left, directions: leftDirections, accumulator: &leftMouse, dt: dt)
        rightDirections = updateStick(profile.right, raw: state.rightRaw, calibration: calibration.right, directions: rightDirections, accumulator: &rightMouse, dt: dt)
        previous = state
    }

    public func releaseAll() {
        lock.lock(); defer { lock.unlock() }
        injector.releaseAll()
        leftDirections = Self.directions(for: profile.left)
        rightDirections = Self.directions(for: profile.right)
        previous = .idle
    }

    private func updatePauseCombo(_ state: ControllerState, time: TimeInterval) {
        guard !profile.pauseCombo.isEmpty else { return }
        let held = profile.pauseCombo.allSatisfy(state.isPressed)
        guard held else {
            comboHeldSince = nil
            comboLatched = false
            return
        }
        if comboHeldSince == nil { comboHeldSince = time }
        guard !comboLatched, let since = comboHeldSince, time - since >= profile.pauseHoldSeconds else { return }
        comboLatched = true
        applyPause(!paused)
    }

    public func setPaused(_ value: Bool) {
        lock.lock(); defer { lock.unlock() }
        guard value != paused else { return }
        applyPause(value)
    }

    private func applyPause(_ value: Bool) {
        paused = value
        injector.releaseAll()
        leftDirections = Self.directions(for: profile.left)
        rightDirections = Self.directions(for: profile.right)
        onPauseChange?(paused)
    }

    private func updateButtons(_ state: ControllerState) {
        let changed = state.buttons ^ previous.buttons
        guard changed != 0 else { return }
        for button in ProController2Button.allCases where changed & button.mask != 0 {
            guard !profile.pauseCombo.contains(button), let binding = profile.bindings[button] else { continue }
            if state.isPressed(button) { injector.press(binding) } else { injector.release(binding) }
        }
    }

    private func updateStick(_ stick: ResolvedStick, raw: StickRaw, calibration: StickCalibration,
                             directions: [DirectionHysteresis], accumulator: inout MouseAccumulator, dt: Double) -> [DirectionHysteresis] {
        let value = calibration.normalize(raw, deadzone: profile.deadzone)
        switch stick.mode {
        case .none:
            return directions
        case let .keys(_, up, down, left, right):
            var updated = directions
            let bindings = [up, down, left, right]
            let values = [value.y, -value.y, -value.x, value.x]
            for index in 0..<4 {
                guard let transition = updated[index].update(values[index]), let binding = bindings[index] else { continue }
                if transition { injector.press(binding) } else { injector.release(binding) }
            }
            return updated
        case let .mouse(sensitivity, curve, invertY, recenter):
            func shape(_ v: Double) -> Double { (v < 0 ? -1.0 : 1.0) * pow(abs(v), curve) * sensitivity * dt }
            let (dx, dy) = accumulator.add(dx: shape(value.x), dy: shape(invertY ? value.y : -value.y))
            injector.moveMouse(dx: dx, dy: dy, recenter: recenter)
            return directions
        }
    }
}
