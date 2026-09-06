import Foundation

public enum NS2Error: Error, CustomStringConvertible {
    case ioKit(String, kern_return_t)
    case usb(String, Error?)
    case deviceNotFound
    case endpointsNotFound
    case hidDeviceNotFound
    case profile(String)

    public var description: String {
        switch self {
        case let .ioKit(what, code):
            return String(format: "%@ failed: 0x%08x", what, UInt32(bitPattern: code))
        case let .usb(what, error):
            return "\(what) failed: \(error.map { String(describing: $0) } ?? "unknown error")"
        case .deviceNotFound:
            return "no supported Nintendo controller found on USB"
        case .endpointsNotFound:
            return "bulk endpoints not found on interface \(USBIDs.bulkInterfaceNumber)"
        case .hidDeviceNotFound:
            return "no HID device for the controller (not woken up yet?)"
        case let .profile(message):
            return message
        }
    }
}
