import Foundation
import IOKit
import IOKit.pwr_mgt

public struct USBDeviceInfo: Sendable {
    public let service: io_service_t
    public let vendorID: UInt16
    public let productID: UInt16
    public let locationID: UInt32
    public let productName: String

    public var description: String {
        String(format: "%@ (%04x:%04x @ 0x%08x)", productName, vendorID, productID, locationID)
    }
}

public enum IORegistry {
    public static func property<T>(_ service: io_service_t, _ key: String) -> T? {
        guard let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }
        return value.takeRetainedValue() as? T
    }

    public static func deviceInfo(_ service: io_service_t) -> USBDeviceInfo? {
        guard let vendor: Int = property(service, "idVendor"),
              let product: Int = property(service, "idProduct"),
              USBIDs.isSupported(vendorID: UInt16(vendor), productID: UInt16(product)) else { return nil }
        let location: Int = property(service, "locationID") ?? 0
        let name: String = property(service, "USB Product Name")
            ?? property(service, "kUSBProductString")
            ?? USBIDs.productName(UInt16(product))
        return USBDeviceInfo(service: service, vendorID: UInt16(vendor), productID: UInt16(product),
                             locationID: UInt32(truncatingIfNeeded: location), productName: name)
    }

    public static func bulkInterfaceMatching() -> CFMutableDictionary {
        let matching = IOServiceMatching("IOUSBHostInterface")! as NSMutableDictionary
        matching["IOPropertyMatch"] = [
            "idVendor": Int(USBIDs.nintendoVendorID),
            "bInterfaceNumber": Int(USBIDs.bulkInterfaceNumber),
        ]
        return matching as CFMutableDictionary
    }

    public static func findBulkInterfaces() -> [USBDeviceInfo] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, bulkInterfaceMatching(), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }
        var result: [USBDeviceInfo] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            if let info = deviceInfo(service) {
                result.append(info)
            } else {
                IOObjectRelease(service)
            }
        }
        return result
    }
}

public final class USBInterfaceWatcher: @unchecked Sendable {
    public typealias Handler = @Sendable (USBDeviceInfo) -> Void

    private static let messageCanSystemSleep: UInt32 = 0xE000_0270
    private static let messageSystemWillSleep: UInt32 = 0xE000_0280
    private static let messageSystemHasPoweredOn: UInt32 = 0xE000_0300

    private let queue = DispatchQueue(label: "com.p1rate.ns2controller.hotplug")
    private let notifyPort: IONotificationPortRef
    private var matchedIterator: io_iterator_t = 0
    private var terminatedIterator: io_iterator_t = 0
    private var powerNotifier: io_object_t = 0
    private var powerPort: IONotificationPortRef?
    private var rootPowerDomain: io_connect_t = 0
    private let onMatched: Handler
    private let onTerminated: Handler
    private let onSystemWake: @Sendable () -> Void

    public init(onMatched: @escaping Handler, onTerminated: @escaping Handler, onSystemWake: @escaping @Sendable () -> Void) {
        self.notifyPort = IONotificationPortCreate(kIOMainPortDefault)
        self.onMatched = onMatched
        self.onTerminated = onTerminated
        self.onSystemWake = onSystemWake
        IONotificationPortSetDispatchQueue(notifyPort, queue)
    }

    public func start() throws {
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        let matchedResult = IOServiceAddMatchingNotification(
            notifyPort, kIOFirstMatchNotification, IORegistry.bulkInterfaceMatching(),
            { refcon, iterator in
                let watcher = Unmanaged<USBInterfaceWatcher>.fromOpaque(refcon!).takeUnretainedValue()
                watcher.drain(iterator, handler: watcher.onMatched)
            }, refcon, &matchedIterator)
        guard matchedResult == KERN_SUCCESS else { throw NS2Error.ioKit("IOServiceAddMatchingNotification(first-match)", matchedResult) }
        drain(matchedIterator, handler: onMatched)

        let terminatedResult = IOServiceAddMatchingNotification(
            notifyPort, kIOTerminatedNotification, IORegistry.bulkInterfaceMatching(),
            { refcon, iterator in
                let watcher = Unmanaged<USBInterfaceWatcher>.fromOpaque(refcon!).takeUnretainedValue()
                watcher.drain(iterator, handler: watcher.onTerminated)
            }, refcon, &terminatedIterator)
        guard terminatedResult == KERN_SUCCESS else { throw NS2Error.ioKit("IOServiceAddMatchingNotification(terminated)", terminatedResult) }
        drain(terminatedIterator, handler: onTerminated)

        var powerPort: IONotificationPortRef?
        rootPowerDomain = IORegisterForSystemPower(refcon, &powerPort, { refcon, service, messageType, argument in
            let watcher = Unmanaged<USBInterfaceWatcher>.fromOpaque(refcon!).takeUnretainedValue()
            watcher.handlePower(messageType: messageType, argument: argument)
        }, &powerNotifier)
        if rootPowerDomain != 0, let powerPort {
            self.powerPort = powerPort
            IONotificationPortSetDispatchQueue(powerPort, queue)
        } else {
            Log.warn("IORegisterForSystemPower failed; sleep/wake re-init disabled")
        }
    }

    private func drain(_ iterator: io_iterator_t, handler: Handler) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            if let info = IORegistry.deviceInfo(service) {
                handler(info)
            }
            IOObjectRelease(service)
        }
    }

    private func handlePower(messageType: natural_t, argument: UnsafeMutableRawPointer?) {
        switch UInt32(messageType) {
        case Self.messageCanSystemSleep, Self.messageSystemWillSleep:
            IOAllowPowerChange(rootPowerDomain, Int(bitPattern: argument))
        case Self.messageSystemHasPoweredOn:
            onSystemWake()
        default:
            break
        }
    }
}
