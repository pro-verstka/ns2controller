import Foundation
import Testing
@testable import NS2Core

private func report(_ prefix: [UInt8]) -> [UInt8] {
    prefix + [UInt8](repeating: 0, count: 64 - prefix.count)
}

private let leftFlashBlock: [UInt8] = {
    var block = [UInt8](repeating: 0xFF, count: 64)
    block.replaceSubrange(0x28..<0x31, with: [0xd4, 0x87, 0x83, 0x2a, 0x06, 0x60, 0x04, 0xc6, 0x5e])
    return block
}()

@Suite struct InputReportTests {
    @Test func parsesCapturedIdleReport() {
        let state = InputReport.parseHID(report([0x09, 0xeb, 0x1b, 0x00, 0x00, 0x00, 0xc6, 0xb7, 0x84, 0x1a, 0xc8, 0x84]))
        #expect(state?.buttons == 0)
        #expect(state?.leftRaw == StickRaw(x: 1990, y: 2123))
        #expect(state?.rightRaw == StickRaw(x: 2074, y: 2124))
        #expect(state?.counter == 0x1beb)
    }

    @Test func mapsButtonBitsToUsages() {
        let state = InputReport.parseHID(report([0x09, 0, 0, 0x01, 0x08, 0x10, 0, 0x08, 0x80, 0, 0x08, 0x80]))!
        #expect(state.pressedButtons == [.b, .dpadUp, .c])
        #expect(state.isPressed(.a) == false)
    }

    @Test func parsesCompactBLEReportLikeHID() {
        let ble: [UInt8] = [0xeb, 0x1b, 0x01, 0x08, 0x10, 0xc6, 0xb7, 0x84, 0x1a, 0xc8, 0x84]
        let state = InputReport.parseCompactBLE(ble)
        #expect(state?.pressedButtons == [.b, .dpadUp, .c])
        #expect(state?.leftRaw == StickRaw(x: 1990, y: 2123))
        #expect(InputReport.parseCompactBLE(Array(ble.prefix(10))) == nil)
    }

    @Test func advertisementFilterMatchesNintendo() {
        #expect(BLEInputSource.isSwitch2Advertisement(name: nil, manufacturerData: Data([0x53, 0x05, 0x01, 0x69, 0x20])))
        #expect(BLEInputSource.isSwitch2Advertisement(name: "Pro Controller", manufacturerData: nil))
        #expect(!BLEInputSource.isSwitch2Advertisement(name: "AirPods", manufacturerData: Data([0x4c, 0x00, 0x01])))
    }

    @Test func rejectsOtherReports() {
        #expect(InputReport.parseHID(report([0x05, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])) == nil)
        #expect(InputReport.parseHID([0x09, 0, 0]) == nil)
    }
}

@Suite struct StickCalibrationTests {
    @Test func decodesFactoryBlock() {
        let calibration = StickCalibration(flashBlock: leftFlashBlock)
        #expect(calibration?.x == AxisCalibration(center: 2004, rangeAbove: 1578, rangeBelow: 1540))
        #expect(calibration?.y == AxisCalibration(center: 2104, rangeAbove: 1536, rangeBelow: 1516))
    }

    @Test func normalizesFullDeflection() {
        let calibration = StickCalibration(flashBlock: leftFlashBlock)!
        #expect(calibration.x.normalize(2004) == 0)
        #expect(calibration.x.normalize(3582) == 1)
        #expect(calibration.x.normalize(464) == -1)
        #expect(calibration.x.normalize(4095) == 1)
        let full = calibration.normalize(StickRaw(x: 3582, y: 2104), deadzone: 0.15)
        #expect(abs(full.x - 1) < 0.001 && full.y == 0)
        let inside = calibration.normalize(StickRaw(x: 2100, y: 2150), deadzone: 0.15)
        #expect(inside.x == 0 && inside.y == 0)
    }

    @Test func rejectsBlankBlock() {
        #expect(StickCalibration(flashBlock: [UInt8](repeating: 0xFF, count: 64)) == nil)
    }
}

@Suite struct BridgeLogicTests {
    @Test func hysteresisPressesAndReleasesAroundThreshold() {
        var direction = DirectionHysteresis(threshold: 0.5)
        #expect(direction.update(0.55) == true)
        #expect(direction.update(0.45) == nil)
        #expect(direction.update(0.35) == false)
        #expect(direction.update(0.45) == nil)
    }

    @Test func mouseAccumulatorCarriesFractions() {
        var accumulator = MouseAccumulator()
        #expect(accumulator.add(dx: 0.4, dy: -0.4) == (0, 0))
        #expect(accumulator.add(dx: 0.4, dy: -0.4) == (0, 0))
        #expect(accumulator.add(dx: 0.4, dy: -0.4) == (1, -1))
    }

    @Test func templateProfileResolves() throws {
        let profile = try KBMProfile.parse(Data(KBMProfile.template.utf8)).resolved()
        #expect(profile.bindings[.a] == .key(49))
        #expect(profile.bindings[.r] == .mouse(.left, number: 0))
        #expect(profile.bindings[.home] == nil)
        #expect(profile.pauseCombo == [.home])
        if case let .keys(threshold, up, _, _, _) = profile.left.mode {
            #expect(threshold == 0.5 && up == .key(13))
        } else {
            Issue.record("left stick should be in keys mode")
        }
    }

    @Test func recenterDefaultsToTrueAndCanBeDisabled() throws {
        let json = KBMProfile.template.replacingOccurrences(of: "\"invert_y\": false", with: "\"invert_y\": false, \"recenter\": false")
        let profile = try KBMProfile.parse(Data(json.utf8)).resolved()
        if case let .mouse(_, _, _, recenter) = profile.right.mode { #expect(recenter == false) } else { Issue.record("mouse mode expected") }
        let defaults = try KBMProfile.parse(Data(KBMProfile.template.utf8)).resolved()
        if case let .mouse(_, _, _, recenter) = defaults.right.mode { #expect(recenter == true) } else { Issue.record("mouse mode expected") }
    }

    @Test func unknownKeyNameFails() {
        let json = KBMProfile.template.replacingOccurrences(of: "\"space\"", with: "\"spaec\"")
        #expect(throws: NS2Error.self) { try KBMProfile.parse(Data(json.utf8)).resolved() }
        do {
            _ = try KBMProfile.parse(Data(json.utf8)).resolved()
        } catch {
            #expect("\(error)".contains("spaec") && "\(error)".contains("buttons.a"))
        }
    }

    @Test func pauseComboTogglesAfterHold() throws {
        let profile = try KBMProfile.parse(Data(KBMProfile.template.utf8)).resolved()
        let injector = EventInjector()
        injector.dryRun = true
        let bridge = KBMBridge(profile: profile, calibration: (.fallback, .fallback), injector: injector)
        var state = ControllerState.idle
        state.buttons = ProController2Button.home.mask
        for tick in 0..<200 { bridge.handle(state, at: Double(tick) * 0.004) }
        #expect(bridge.paused == false)
        for tick in 200..<300 { bridge.handle(state, at: Double(tick) * 0.004) }
        #expect(bridge.paused == true)
        state.buttons = 0
        bridge.handle(state, at: 1.3)
        state.buttons = ProController2Button.a.mask
        bridge.handle(state, at: 1.31)
        #expect(injector.held.keys == 0)
        state.buttons = ProController2Button.home.mask
        for tick in 0..<300 { bridge.handle(state, at: 1.4 + Double(tick) * 0.004) }
        #expect(bridge.paused == false)
    }

    @Test func bridgePressesBoundKeysAndStickDirections() throws {
        let profile = try KBMProfile.parse(Data(KBMProfile.template.utf8)).resolved()
        let injector = EventInjector()
        injector.dryRun = true
        let bridge = KBMBridge(profile: profile, calibration: (.fallback, .fallback), injector: injector)
        var state = ControllerState.idle
        state.buttons = ProController2Button.a.mask
        bridge.handle(state, at: 0)
        #expect(injector.held.keys == 1)
        state.buttons = 0
        state.leftRaw = StickRaw(x: 3600, y: 2048)
        bridge.handle(state, at: 0.004)
        #expect(injector.held.keys == 1)
        state.leftRaw = StickRaw(x: 2048, y: 2048)
        bridge.handle(state, at: 0.008)
        #expect(injector.held.keys == 0)
        bridge.releaseAll()
        #expect(injector.held == (0, 0))
    }
}
