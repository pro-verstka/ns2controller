import Foundation
import NS2Core

final class Daemon: @unchecked Sendable {
    private let variant: WakeUpSequence.Variant
    private let format: WakeUpSequence.InputReportFormat
    private let playerLED: Int?
    private let holdInterface: Bool
    private var held: [UInt32: BulkTransport] = [:]
    private var watcher: USBInterfaceWatcher?

    init(variant: WakeUpSequence.Variant, format: WakeUpSequence.InputReportFormat, playerLED: Int?, holdInterface: Bool) {
        self.variant = variant
        self.format = format
        self.playerLED = playerLED
        self.holdInterface = holdInterface
    }

    func start() throws {
        Log.info("ns2ctl daemon starting (variant=\(variant.rawValue), format=0x\(String(format.rawValue, radix: 16)), hold=\(holdInterface))")
        let watcher = USBInterfaceWatcher(
            onMatched: { [self] info in wake(info) },
            onTerminated: { [self] info in
                Log.info("removed: \(info.description)")
                held.removeValue(forKey: info.locationID)?.close()
            },
            onSystemWake: { [self] in
                Log.info("system woke up, re-initializing controllers")
                Thread.sleep(forTimeInterval: 2.0)
                for info in IORegistry.findBulkInterfaces() {
                    wake(info)
                    IOObjectRelease(info.service)
                }
            })
        try watcher.start()
        self.watcher = watcher
    }

    private func wake(_ info: USBDeviceInfo) {
        Log.info("detected: \(info.description)")
        held.removeValue(forKey: info.locationID)?.close()
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
                if holdInterface { held[info.locationID] = transport } else { transport.close() }
                let reports = (try? HIDMonitor.sample(duration: 0.5))?.counts[UInt32(format.rawValue)] ?? 0
                if reports > 0 {
                    Log.info("HID report 0x\(String(format.rawValue, radix: 16)) flowing: \(reports) reports in 0.5s")
                    return
                }
                Log.warn("no HID reports after wake (attempt \(attempt)), retrying")
                held.removeValue(forKey: info.locationID)?.close()
            } catch {
                Log.warn("wake attempt \(attempt) failed: \(error)")
            }
        }
        Log.error("giving up on \(info.description)")
    }
}
