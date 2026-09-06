import Foundation
import IOKit
import IOKit.hid

public final class HIDMonitor {
    public struct Options: Sendable {
        public var showReports = true
        public var showValues = false
        public var axisDeadband = 96
        public init() {}
    }

    private final class DeviceState {
        let device: IOHIDDevice
        let buffer: UnsafeMutablePointer<UInt8>
        let bufferSize: Int
        var lastReports: [UInt32: [UInt8]] = [:]
        var lastValues: [UInt64: Int] = [:]

        init(device: IOHIDDevice, bufferSize: Int) {
            self.device = device
            self.bufferSize = bufferSize
            buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        }

        deinit { buffer.deallocate() }
    }

    private let manager: IOHIDManager
    private let options: Options
    private var devices: [DeviceState] = []

    public static var matchingDictionaries: [[String: Any]] {
        USBIDs.supportedProductIDs.map { productID in
            [kIOHIDVendorIDKey: Int(USBIDs.nintendoVendorID), kIOHIDProductIDKey: Int(productID)]
        }
    }

    public init(options: Options = Options()) {
        self.options = options
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatchingMultiple(manager, Self.matchingDictionaries as CFArray)
    }

    public static func devices() -> [IOHIDDevice] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatchingMultiple(manager, matchingDictionaries as CFArray)
        guard let set = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }
        return Array(set)
    }

    public static func describe(_ device: IOHIDDevice) -> String {
        func prop<T>(_ key: String) -> T? { IOHIDDeviceGetProperty(device, key as CFString) as? T }
        var lines: [String] = []
        let product: String = prop(kIOHIDProductKey) ?? "?"
        let vendor: Int = prop(kIOHIDVendorIDKey) ?? 0
        let productID: Int = prop(kIOHIDProductIDKey) ?? 0
        let transport: String = prop(kIOHIDTransportKey) ?? "?"
        let usagePage: Int = prop(kIOHIDPrimaryUsagePageKey) ?? 0
        let usage: Int = prop(kIOHIDPrimaryUsageKey) ?? 0
        let maxIn: Int = prop(kIOHIDMaxInputReportSizeKey) ?? 0
        let maxOut: Int = prop(kIOHIDMaxOutputReportSizeKey) ?? 0
        let maxFeature: Int = prop(kIOHIDMaxFeatureReportSizeKey) ?? 0
        lines.append(String(format: "%@  vid=0x%04x pid=0x%04x transport=%@ usage=%d:%d", product, vendor, productID, transport, usagePage, usage))
        lines.append("max report sizes: input=\(maxIn) output=\(maxOut) feature=\(maxFeature)")
        if let descriptor: Data = prop(kIOHIDReportDescriptorKey) {
            lines.append("report descriptor (\(descriptor.count) bytes): \([UInt8](descriptor).hexString)")
        }
        if let elements = IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement] {
            lines.append("elements (\(elements.count)):")
            for element in elements {
                let type = IOHIDElementGetType(element)
                let typeName: String
                switch type {
                case kIOHIDElementTypeInput_Misc: typeName = "in.misc"
                case kIOHIDElementTypeInput_Button: typeName = "in.button"
                case kIOHIDElementTypeInput_Axis: typeName = "in.axis"
                case kIOHIDElementTypeInput_ScanCodes: typeName = "in.scan"
                case kIOHIDElementTypeOutput: typeName = "out"
                case kIOHIDElementTypeFeature: typeName = "feature"
                case kIOHIDElementTypeCollection: typeName = "collection"
                default: typeName = "type\(type.rawValue)"
                }
                lines.append(String(format: "  %-10@ report=%d page=0x%02x usage=0x%02x size=%d count=%d logical=[%d..%d] cookie=%u",
                                    typeName, IOHIDElementGetReportID(element),
                                    IOHIDElementGetUsagePage(element), IOHIDElementGetUsage(element),
                                    IOHIDElementGetReportSize(element), IOHIDElementGetReportCount(element),
                                    IOHIDElementGetLogicalMin(element), IOHIDElementGetLogicalMax(element),
                                    IOHIDElementGetCookie(element)))
            }
        }
        return lines.joined(separator: "\n")
    }

    public struct Sample: Sendable {
        public var counts: [UInt32: Int] = [:]
        public var lastReports: [UInt32: [UInt8]] = [:]
    }

    private final class SampleBox {
        var sample = Sample()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 256)
        deinit { buffer.deallocate() }
    }

    public static func sample(duration: TimeInterval) throws -> Sample {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatchingMultiple(manager, matchingDictionaries as CFArray)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else { throw NS2Error.ioKit("IOHIDManagerOpen", result) }
        defer {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        let box = SampleBox()
        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        for device in devices {
            IOHIDDeviceRegisterInputReportCallback(device, box.buffer, 256, { refcon, _, _, _, reportID, report, length in
                let box = Unmanaged<SampleBox>.fromOpaque(refcon!).takeUnretainedValue()
                box.sample.counts[reportID, default: 0] += 1
                box.sample.lastReports[reportID] = Array(UnsafeBufferPointer(start: report, count: length))
            }, Unmanaged.passUnretained(box).toOpaque())
        }
        CFRunLoopRunInMode(CFRunLoopMode.defaultMode, duration, false)
        for device in devices {
            IOHIDDeviceRegisterInputReportCallback(device, box.buffer, 256, nil, nil)
        }
        return box.sample
    }

    public func run() throws {
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { refcon, _, _, device in
            let monitor = Unmanaged<HIDMonitor>.fromOpaque(refcon!).takeUnretainedValue()
            monitor.attach(device)
        }, refcon)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { refcon, _, _, device in
            let monitor = Unmanaged<HIDMonitor>.fromOpaque(refcon!).takeUnretainedValue()
            monitor.detach(device)
        }, refcon)
        if options.showValues {
            IOHIDManagerRegisterInputValueCallback(manager, { refcon, _, _, value in
                let monitor = Unmanaged<HIDMonitor>.fromOpaque(refcon!).takeUnretainedValue()
                monitor.handle(value: value)
            }, refcon)
        }
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else { throw NS2Error.ioKit("IOHIDManagerOpen", result) }
        Log.info("monitoring HID devices, press Ctrl+C to stop")
        CFRunLoopRun()
    }

    private func attach(_ device: IOHIDDevice) {
        let size = (IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? Int) ?? 64
        let state = DeviceState(device: device, bufferSize: max(size, 64))
        devices.append(state)
        Log.info("attached: \(Self.describe(device).components(separatedBy: "\n").first ?? "")")
        guard options.showReports else { return }
        let refcon = Unmanaged.passUnretained(state).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, state.buffer, state.bufferSize, { refcon, _, _, _, reportID, report, length in
            let state = Unmanaged<DeviceState>.fromOpaque(refcon!).takeUnretainedValue()
            HIDMonitor.handle(report: Array(UnsafeBufferPointer(start: report, count: length)), reportID: reportID, state: state)
        }, refcon)
    }

    private func detach(_ device: IOHIDDevice) {
        devices.removeAll { $0.device == device }
        Log.info("detached HID device")
    }

    private static func handle(report: [UInt8], reportID: UInt32, state: DeviceState) {
        guard let previous = state.lastReports[reportID] else {
            state.lastReports[reportID] = report
            Log.info("report id=\(reportID) len=\(report.count): \(report.hexString)")
            return
        }
        guard previous != report else { return }
        var changes: [String] = []
        for index in 0..<max(previous.count, report.count) {
            let old = index < previous.count ? previous[index] : 0
            let new = index < report.count ? report[index] : 0
            if old != new {
                changes.append(String(format: "[%d] %02x->%02x (^%02x)", index, old, new, old ^ new))
            }
        }
        state.lastReports[reportID] = report
        Log.info("report id=\(reportID): \(changes.joined(separator: " "))")
    }

    private func handle(value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let page = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        guard page == 0x01 || page == 0x09 else { return }
        let integer = IOHIDValueGetIntegerValue(value)
        let key = UInt64(page) << 32 | UInt64(usage)
        guard let state = devices.first else { return }
        if page == 0x01, (0x30...0x39).contains(usage) {
            if let last = state.lastValues[key], abs(last - integer) < options.axisDeadband { return }
        } else if state.lastValues[key] == integer {
            return
        }
        state.lastValues[key] = integer
        Log.info(String(format: "value page=0x%02x usage=0x%02x %@ = %d", page, usage, Self.usageName(page: page, usage: usage), integer))
    }

    private static func usageName(page: UInt32, usage: UInt32) -> String {
        switch (page, usage) {
        case (0x01, 0x30): return "X"
        case (0x01, 0x31): return "Y"
        case (0x01, 0x32): return "Z"
        case (0x01, 0x33): return "Rx"
        case (0x01, 0x34): return "Ry"
        case (0x01, 0x35): return "Rz"
        case (0x01, 0x39): return "Hat"
        case (0x09, _): return ProController2Button(rawValue: Int(usage)).map { "Button\(usage) (\($0.name))" } ?? "Button\(usage)"
        default: return ""
        }
    }
}
