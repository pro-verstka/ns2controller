import Foundation

public struct StickRaw: Equatable, Sendable {
    public var x: Int
    public var y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

public struct ControllerState: Equatable, Sendable {
    public var buttons: UInt32
    public var leftRaw: StickRaw
    public var rightRaw: StickRaw
    public var counter: UInt16

    public init(buttons: UInt32, leftRaw: StickRaw, rightRaw: StickRaw, counter: UInt16) {
        self.buttons = buttons
        self.leftRaw = leftRaw
        self.rightRaw = rightRaw
        self.counter = counter
    }

    public static let idle = ControllerState(buttons: 0, leftRaw: StickRaw(x: 2048, y: 2048), rightRaw: StickRaw(x: 2048, y: 2048), counter: 0)

    public func isPressed(_ button: ProController2Button) -> Bool {
        buttons & button.mask != 0
    }

    public var pressedButtons: [ProController2Button] {
        ProController2Button.allCases.filter(isPressed)
    }
}

public extension ProController2Button {
    var mask: UInt32 { 1 << UInt32(hidUsage - 1) }
}

public enum InputReport {
    public static let hidReportID: UInt8 = 0x09
    public static let minimumLength = 12

    public static func parseHID(_ bytes: [UInt8]) -> ControllerState? {
        guard bytes.count >= minimumLength, bytes[0] == hidReportID else { return nil }
        let counter = UInt16(bytes[1]) | UInt16(bytes[2]) << 8
        let buttons = (UInt32(bytes[3]) | UInt32(bytes[4]) << 8 | UInt32(bytes[5]) << 16) & 0x1F_FFFF
        return ControllerState(buttons: buttons, leftRaw: stick(bytes, at: 6), rightRaw: stick(bytes, at: 9), counter: counter)
    }

    public static func parseCompactBLE(_ bytes: [UInt8]) -> ControllerState? {
        guard bytes.count >= 11 else { return nil }
        return parseHID([hidReportID] + bytes)
    }

    static func stick(_ bytes: [UInt8], at offset: Int) -> StickRaw {
        StickRaw(x: Int(bytes[offset]) | (Int(bytes[offset + 1] & 0x0F) << 8),
                 y: Int(bytes[offset + 1] >> 4) | (Int(bytes[offset + 2]) << 4))
    }
}
