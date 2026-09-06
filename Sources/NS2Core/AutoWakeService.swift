import Foundation
import IOKit

public final class AutoWakeService: @unchecked Sendable {
    public enum Event: Sendable {
        case detected(String)
        case woke(String, replies: Int, total: Int)
        case failed(String)
        case removed(String)
        case systemWake
    }

    private let lock = NSLock()
    private var _playerLED: Int?
    private var _variant: WakeUpSequence.Variant
    private var _format: WakeUpSequence.InputReportFormat
    private let holdInterface: Bool
    private var held: [UInt32: BulkTransport] = [:]
    private var watcher: USBInterfaceWatcher?
    public var onEvent: (@Sendable (Event) -> Void)?

    public var playerLED: Int? {
        get { lock.lock(); defer { lock.unlock() }; return _playerLED }
        set { lock.lock(); _playerLED = newValue; lock.unlock() }
    }

    public var variant: WakeUpSequence.Variant {
        get { lock.lock(); defer { lock.unlock() }; return _variant }
        set { lock.lock(); _variant = newValue; lock.unlock() }
    }

    public var format: WakeUpSequence.InputReportFormat {
        get { lock.lock(); defer { lock.unlock() }; return _format }
        set { lock.lock(); _format = newValue; lock.unlock() }
    }

    public var isRunning: Bool { watcher != nil }

    public init(variant: WakeUpSequence.Variant = .sdl, format: WakeUpSequence.InputReportFormat = .hid,
                playerLED: Int? = nil, holdInterface: Bool = false) {
        _variant = variant
        _format = format
        _playerLED = playerLED
        self.holdInterface = holdInterface
    }

    public func start() throws {
        guard watcher == nil else { return }
        Log.info("auto-wake starting (variant=\(variant.rawValue), format=0x\(String(format.rawValue, radix: 16)), hold=\(holdInterface))")
        let watcher = USBInterfaceWatcher(
            onMatched: { [self] info in wake(info) },
            onTerminated: { [self] info in
                Log.info("removed: \(info.description)")
                lock.lock(); let transport = held.removeValue(forKey: info.locationID); lock.unlock()
                transport?.close()
                onEvent?(.removed(info.productName))
            },
            onSystemWake: { [self] in
                Log.info("system woke up, re-initializing controllers")
                onEvent?(.systemWake)
                Thread.sleep(forTimeInterval: 2.0)
                wakeAll()
            })
        try watcher.start()
        self.watcher = watcher
    }

    public func stop() {
        watcher?.stop()
        watcher = nil
        lock.lock(); let transports = held; held.removeAll(); lock.unlock()
        transports.values.forEach { $0.close() }
    }

    @discardableResult
    public func wakeAll() -> Int {
        var count = 0
        for info in IORegistry.findBulkInterfaces() {
            if wake(info) { count += 1 }
            IOObjectRelease(info.service)
        }
        return count
    }

    @discardableResult
    private func wake(_ info: USBDeviceInfo) -> Bool {
        Log.info("detected: \(info.description)")
        onEvent?(.detected(info.productName))
        lock.lock(); let previous = held.removeValue(forKey: info.locationID); lock.unlock()
        previous?.close()
        for attempt in 1...3 {
            Thread.sleep(forTimeInterval: attempt == 1 ? 0.3 : 1.0)
            do {
                let transport = try BulkTransport(service: info.service)
                let controller = Controller(transport: transport)
                let results = controller.wake(variant: variant, format: format)
                let replies = results.filter { !$0.reply.isEmpty }.count
                let errors = results.filter { $0.error != nil }.count
                if let playerLED { controller.setPlayerLED(playerLED) }
                Log.info("woke \(info.productName): \(replies)/\(results.count) replies, \(errors) errors (attempt \(attempt))")
                if holdInterface {
                    lock.lock(); held[info.locationID] = transport; lock.unlock()
                } else {
                    transport.close()
                }
                let reports = (try? HIDMonitor.sample(duration: 0.5))?.counts[UInt32(format.rawValue)] ?? 0
                if reports > 0 {
                    Log.info("HID report 0x\(String(format.rawValue, radix: 16)) flowing: \(reports) reports in 0.5s")
                    onEvent?(.woke(info.productName, replies: replies, total: results.count))
                    return true
                }
                Log.warn("no HID reports after wake (attempt \(attempt)), retrying")
                lock.lock(); let stale = held.removeValue(forKey: info.locationID); lock.unlock()
                stale?.close()
            } catch {
                Log.warn("wake attempt \(attempt) failed: \(error)")
            }
        }
        Log.error("giving up on \(info.description)")
        onEvent?(.failed(info.productName))
        return false
    }
}
