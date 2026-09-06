import Foundation
import IOKit
import IOKit.hid

public final class HIDInputSource: @unchecked Sendable {
    public typealias StateHandler = @Sendable (ControllerState) -> Void
    public typealias DeviceHandler = @Sendable (String) -> Void

    private final class DeviceBuffer {
        let device: IOHIDDevice
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 256)
        init(device: IOHIDDevice) { self.device = device }
        deinit { buffer.deallocate() }
    }

    private let manager: IOHIDManager
    private let exclusive: Bool
    private let onState: StateHandler
    private let onAttach: DeviceHandler
    private let onDetach: DeviceHandler
    private var buffers: [DeviceBuffer] = []
    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private let started = DispatchSemaphore(value: 0)
    public var onRawReport: (@Sendable ([UInt8]) -> Void)?
    public private(set) var isAttached = false

    public init(exclusive: Bool, onAttach: @escaping DeviceHandler, onDetach: @escaping DeviceHandler, onState: @escaping StateHandler) {
        self.exclusive = exclusive
        self.onAttach = onAttach
        self.onDetach = onDetach
        self.onState = onState
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatchingMultiple(manager, HIDMonitor.matchingDictionaries as CFArray)
    }

    public func start() throws {
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { refcon, _, _, device in
            Unmanaged<HIDInputSource>.fromOpaque(refcon!).takeUnretainedValue().attach(device)
        }, refcon)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { refcon, _, _, device in
            Unmanaged<HIDInputSource>.fromOpaque(refcon!).takeUnretainedValue().detach(device)
        }, refcon)
        var openResult = kIOReturnSuccess
        let thread = Thread { [self] in
            runLoop = CFRunLoopGetCurrent()
            IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            let options = IOOptionBits(exclusive ? kIOHIDOptionsTypeSeizeDevice : kIOHIDOptionsTypeNone)
            openResult = IOHIDManagerOpen(manager, options)
            if openResult != kIOReturnSuccess, exclusive {
                Log.warn(String(format: "exclusive access denied (0x%08x), falling back to shared mode", UInt32(bitPattern: openResult)))
                openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            }
            started.signal()
            guard openResult == kIOReturnSuccess else { return }
            CFRunLoopRun()
        }
        thread.name = "com.p1rate.ns2controller.hid-input"
        thread.start()
        self.thread = thread
        started.wait()
        guard openResult == kIOReturnSuccess else { throw NS2Error.ioKit("IOHIDManagerOpen", openResult) }
    }

    public func stop() {
        if let runLoop { CFRunLoopStop(runLoop) }
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    private func attach(_ device: IOHIDDevice) {
        let entry = DeviceBuffer(device: device)
        buffers.append(entry)
        isAttached = true
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, entry.buffer, 256, { refcon, _, _, _, _, report, length in
            let source = Unmanaged<HIDInputSource>.fromOpaque(refcon!).takeUnretainedValue()
            let bytes = Array(UnsafeBufferPointer(start: report, count: length))
            source.onRawReport?(bytes)
            guard let state = InputReport.parseHID(bytes) else { return }
            source.onState(state)
        }, refcon)
        onAttach(HIDMonitor.describe(device).components(separatedBy: "\n").first ?? "controller")
    }

    private func detach(_ device: IOHIDDevice) {
        buffers.removeAll { $0.device == device }
        isAttached = !buffers.isEmpty
        onDetach("controller")
    }
}
