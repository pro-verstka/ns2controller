import Foundation

public enum USBIDs {
    public static let nintendoVendorID: UInt16 = 0x057E

    public static let proController2: UInt16 = 0x2069
    public static let gameCubeController: UInt16 = 0x2073
    public static let joyCon2Left: UInt16 = 0x2066
    public static let joyCon2Right: UInt16 = 0x2067

    public static let supportedProductIDs: [UInt16] = [
        proController2, gameCubeController, joyCon2Left, joyCon2Right,
    ]

    public static let bulkInterfaceNumber: UInt8 = 1

    public static func productName(_ productID: UInt16) -> String {
        switch productID {
        case proController2: return "Switch 2 Pro Controller"
        case gameCubeController: return "NSO GameCube Controller (Switch 2)"
        case joyCon2Left: return "Joy-Con 2 (L)"
        case joyCon2Right: return "Joy-Con 2 (R)"
        default: return String(format: "Nintendo device 0x%04X", productID)
        }
    }

    public static func isSupported(vendorID: UInt16, productID: UInt16) -> Bool {
        vendorID == nintendoVendorID && supportedProductIDs.contains(productID)
    }
}
