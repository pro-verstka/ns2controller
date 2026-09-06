import Foundation

public struct AxisCalibration: Equatable, Sendable {
    public var center: Int
    public var rangeAbove: Int
    public var rangeBelow: Int

    public init(center: Int, rangeAbove: Int, rangeBelow: Int) {
        self.center = center
        self.rangeAbove = rangeAbove
        self.rangeBelow = rangeBelow
    }

    public func normalize(_ raw: Int) -> Double {
        let delta = raw - center
        let range = delta >= 0 ? rangeAbove : rangeBelow
        guard range > 0 else { return 0 }
        return max(-1, min(1, Double(delta) / Double(range)))
    }
}

public struct StickCalibration: Equatable, Sendable {
    public static let leftFlashAddress: UInt32 = 0x13080
    public static let rightFlashAddress: UInt32 = 0x130C0
    public static let flashDataOffset = 0x28
    public static let fallback = StickCalibration(
        x: AxisCalibration(center: 2048, rangeAbove: 1550, rangeBelow: 1550),
        y: AxisCalibration(center: 2048, rangeAbove: 1550, rangeBelow: 1550))

    public var x: AxisCalibration
    public var y: AxisCalibration

    public init(x: AxisCalibration, y: AxisCalibration) {
        self.x = x
        self.y = y
    }

    public init?(flashBlock: [UInt8]) {
        let offset = Self.flashDataOffset
        guard flashBlock.count >= offset + 9 else { return nil }
        let center = Self.pair(flashBlock, at: offset)
        let above = Self.pair(flashBlock, at: offset + 3)
        let below = Self.pair(flashBlock, at: offset + 6)
        let plausible = (1..<4095).contains(center.0) && (1..<4095).contains(center.1)
            && above.0 > 100 && above.1 > 100 && below.0 > 100 && below.1 > 100
        guard plausible else { return nil }
        x = AxisCalibration(center: center.0, rangeAbove: above.0, rangeBelow: below.0)
        y = AxisCalibration(center: center.1, rangeAbove: above.1, rangeBelow: below.1)
    }

    static func pair(_ bytes: [UInt8], at offset: Int) -> (Int, Int) {
        (Int(bytes[offset]) | (Int(bytes[offset + 1] & 0x0F) << 8),
         Int(bytes[offset + 1] >> 4) | (Int(bytes[offset + 2]) << 4))
    }

    public func normalize(_ raw: StickRaw, deadzone: Double) -> (x: Double, y: Double) {
        let nx = x.normalize(raw.x)
        let ny = y.normalize(raw.y)
        let magnitude = (nx * nx + ny * ny).squareRoot()
        guard magnitude > deadzone, deadzone < 1 else { return (0, 0) }
        let scaled = min(1, (magnitude - deadzone) / (1 - deadzone))
        return (nx / magnitude * scaled, ny / magnitude * scaled)
    }

    public static func read(using controller: Controller) -> (left: StickCalibration, right: StickCalibration) {
        func block(_ address: UInt32) -> StickCalibration? {
            guard let data = try? controller.readFlash(address: address) else { return nil }
            return StickCalibration(flashBlock: data)
        }
        let left = block(leftFlashAddress)
        let right = block(rightFlashAddress)
        if left == nil || right == nil {
            Log.warn("stick calibration not readable from flash, using defaults")
        }
        return (left ?? .fallback, right ?? .fallback)
    }
}
