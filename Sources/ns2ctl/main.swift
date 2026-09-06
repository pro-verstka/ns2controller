import AppKit
import Foundation
import CoreGraphics
import NS2Core

let usage = """
ns2ctl — Nintendo Switch 2 controllers over USB on macOS

Usage:
  ns2ctl wake [--variant sdl|extended] [--format 9|5] [--led N] [--hold SECONDS] [-v]
  ns2ctl daemon [--variant sdl|extended] [--format 9|5] [--led N] [--hold] [-v]
  ns2ctl format 9|5                    switch input report format on a woken controller
  ns2ctl reset                         reset the controller (USB re-enumeration)
  ns2ctl list
  ns2ctl info
  ns2ctl monitor [--values] [--no-reports] [-v]
  ns2ctl led N [-v]
  ns2ctl flash 0xADDRESS [-v]
  ns2ctl kbm [--profile NAME] [--exclusive] [--dry-run] [-v]
                                       keyboard/mouse bridge (needs Accessibility permission)
  ns2ctl kbm --init-profile NAME [--force]   write a profile template
  ns2ctl kbm --list-profiles
  ns2ctl kbm --self-test               move the cursor and tap Shift to verify Accessibility
  ns2ctl steam-mapping                 print SDL_GAMECONTROLLERCONFIG lines for Steam
  ns2ctl send HEXBYTES... [-v]        send one raw bulk command, print reply
  ns2ctl sample [SECONDS]              histogram of HID input report IDs
"""

struct Arguments {
    var command: String
    var flags: Set<String> = []
    var values: [String: String] = [:]
    var positional: [String] = []

    init(_ args: [String]) {
        command = args.first ?? "help"
        var index = 1
        while index < args.count {
            let arg = args[index]
            if arg.hasPrefix("--"), index + 1 < args.count, !args[index + 1].hasPrefix("-"),
               ["--variant", "--led", "--hold", "--format", "--profile", "--init-profile"].contains(arg) {
                values[arg] = args[index + 1]
                index += 2
                continue
            }
            if arg.hasPrefix("-") { flags.insert(arg) } else { positional.append(arg) }
            index += 1
        }
    }
}

func fail(_ message: String) -> Never {
    Log.error(message)
    exit(1)
}

func variant(from arguments: Arguments) -> WakeUpSequence.Variant {
    guard let raw = arguments.values["--variant"] else { return .sdl }
    guard let variant = WakeUpSequence.Variant(rawValue: raw) else { fail("unknown variant \(raw)") }
    return variant
}

func reportFormat(from arguments: Arguments, positional: Bool = false) -> WakeUpSequence.InputReportFormat {
    let raw = positional ? arguments.positional.first : arguments.values["--format"]
    guard let raw else { return .hid }
    guard let value = UInt8(raw.replacingOccurrences(of: "0x", with: ""), radix: raw.hasPrefix("0x") ? 16 : 10),
          let format = WakeUpSequence.InputReportFormat(rawValue: value) else { fail("format must be 9 (HID) or 5 (vendor)") }
    return format
}

func formatCommand(_ arguments: Arguments) {
    let format = reportFormat(from: arguments, positional: true)
    do {
        let controller = Controller(transport: try BulkTransport())
        let result = controller.setInputReportFormat(format)
        Log.info("input report format 0x\(String(format.rawValue, radix: 16)): \(result.error ?? (result.reply.isEmpty ? "no reply" : "ok"))")
    } catch { fail("\(error)") }
}

func resetCommand() {
    do {
        let controller = Controller(transport: try BulkTransport())
        Log.info("resetting \(controller.info.description)")
        controller.reset()
    } catch { fail("\(error)") }
}

func wakeCommand(_ arguments: Arguments) {
    let transport: BulkTransport
    do { transport = try BulkTransport() } catch { fail("\(error)") }
    let controller = Controller(transport: transport)
    let chosen = variant(from: arguments)
    let format = reportFormat(from: arguments)
    Log.info("waking \(controller.info.description) with \(chosen.rawValue) sequence, report format 0x\(String(format.rawValue, radix: 16))")
    let results = controller.wake(variant: chosen, format: format)
    let failures = results.filter { $0.error != nil }
    let replies = results.filter { !$0.reply.isEmpty }.count
    Log.info("sent \(results.count) commands, \(replies) replies, \(failures.count) errors")
    for failure in failures { Log.warn("\(failure.command.name): \(failure.error ?? "")") }
    if let led = arguments.values["--led"].flatMap(Int.init) {
        let result = controller.setPlayerLED(led)
        Log.info("player LED \(led): \(result.error ?? (result.reply.isEmpty ? "no reply" : "ok"))")
    }
    if let hold = arguments.values["--hold"].flatMap(Double.init) {
        Log.info("holding interface open for \(hold)s")
        Thread.sleep(forTimeInterval: hold)
    }
    transport.close()
}

func listCommand() {
    let interfaces = IORegistry.findBulkInterfaces()
    if interfaces.isEmpty { Log.info("no supported controllers on USB") }
    for info in interfaces {
        Log.info("USB: \(info.description)")
        IOObjectRelease(info.service)
    }
    for device in HIDMonitor.devices() {
        Log.info("HID: \(HIDMonitor.describe(device).components(separatedBy: "\n").first ?? "")")
    }
}

func infoCommand() {
    let devices = HIDMonitor.devices()
    if devices.isEmpty { fail("\(NS2Error.hidDeviceNotFound)") }
    for device in devices {
        print(HIDMonitor.describe(device))
    }
}

func monitorCommand(_ arguments: Arguments) {
    var options = HIDMonitor.Options()
    options.showValues = arguments.flags.contains("--values")
    options.showReports = !arguments.flags.contains("--no-reports")
    let monitor = HIDMonitor(options: options)
    do { try monitor.run() } catch { fail("\(error)") }
}

func ledCommand(_ arguments: Arguments) {
    guard let player = arguments.positional.first.flatMap(Int.init), (1...8).contains(player) else { fail("usage: ns2ctl led N (1-8)") }
    do {
        let controller = Controller(transport: try BulkTransport())
        let result = controller.setPlayerLED(player)
        Log.info("player LED \(player): \(result.error ?? (result.reply.isEmpty ? "no reply" : "reply \(result.reply.hexString)"))")
    } catch { fail("\(error)") }
}

func flashCommand(_ arguments: Arguments) {
    guard let raw = arguments.positional.first,
          let address = UInt32(raw.replacingOccurrences(of: "0x", with: ""), radix: 16) else { fail("usage: ns2ctl flash 0xADDRESS") }
    do {
        let controller = Controller(transport: try BulkTransport())
        let data = try controller.readFlash(address: address)
        Log.info(String(format: "flash 0x%06X (%d bytes): %@", address, data.count, data.hexString))
    } catch { fail("\(error)") }
}

func sendCommand(_ arguments: Arguments) {
    let bytes = arguments.positional.joined(separator: " ").split(separator: " ").compactMap { UInt8($0, radix: 16) }
    guard bytes.count >= 8 else { fail("usage: ns2ctl send 0c 91 00 02 00 04 00 00 27 00 00 00") }
    do {
        let controller = Controller(transport: try BulkTransport())
        let result = controller.execute(BulkCommand("manual", bytes))
        Log.info("sent \(bytes.hexString) -> \(result.error ?? (result.reply.isEmpty ? "no reply" : result.reply.hexString))")
    } catch { fail("\(error)") }
}

func sampleCommand(_ arguments: Arguments) {
    let seconds = arguments.positional.first.flatMap(Double.init) ?? 1.0
    do {
        let sample = try HIDMonitor.sample(duration: seconds)
        if sample.counts.isEmpty { Log.info("no input reports in \(seconds)s") }
        for (id, count) in sample.counts.sorted(by: { $0.key < $1.key }) {
            Log.info("report id=\(id): \(count) reports, last: \(sample.lastReports[id]?.hexString ?? "")")
        }
    } catch { fail("\(error)") }
}

nonisolated(unsafe) var signalSources: [DispatchSourceSignal] = []

func installSignalHandlers(_ handler: @escaping @Sendable () -> Void) {
    for sig in [SIGINT, SIGTERM] {
        signal(sig, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        source.setEventHandler(handler: handler)
        source.resume()
        signalSources.append(source)
    }
}

func kbmCommand(_ arguments: Arguments) {
    if arguments.flags.contains("--list-profiles") {
        let names = KBMProfile.list()
        print(names.isEmpty ? "no profiles in \(KBMProfile.directory.path)" : names.joined(separator: "\n"))
        return
    }
    if arguments.flags.contains("--self-test") {
        guard EventInjector.isAccessibilityTrusted(prompt: true) else {
            Log.error("not trusted for Accessibility")
            EventInjector.openAccessibilitySettings()
            exit(1)
        }
        let injector = EventInjector()
        let before = CGEvent(source: nil)?.location ?? .zero
        injector.moveMouse(dx: 30, dy: 0)
        Thread.sleep(forTimeInterval: 0.2)
        let moved = CGEvent(source: nil)?.location ?? .zero
        injector.moveMouse(dx: -30, dy: 0)
        injector.press(.key(CGKeyCode(56)))
        injector.release(.key(CGKeyCode(56)))
        let ok = abs(moved.x - before.x - 30) < 2
        Log.info(String(format: "cursor %.0f,%.0f -> %.0f,%.0f, shift tapped: %@", before.x, before.y, moved.x, moved.y, ok ? "OK" : "cursor did not move"))
        exit(ok ? 0 : 1)
    }
    if let name = arguments.values["--init-profile"] {
        do {
            let url = try KBMProfile.writeTemplate(name: name, overwrite: arguments.flags.contains("--force"))
            Log.info("profile: \(url.path)")
        } catch { fail("\(error)") }
        return
    }
    let name = arguments.values["--profile"] ?? "default"
    let profile: ResolvedProfile
    do { profile = try KBMProfile.load(name: name).resolved() } catch { fail("\(error)") }
    let dryRun = arguments.flags.contains("--dry-run")
    if !dryRun, !EventInjector.isAccessibilityTrusted(prompt: true) {
        Log.error("Accessibility permission required: System Settings → Privacy & Security → Accessibility → enable the terminal app that runs ns2ctl, then restart")
        EventInjector.openAccessibilitySettings()
        exit(1)
    }
    var calibration = (left: StickCalibration.fallback, right: StickCalibration.fallback)
    if let transport = try? BulkTransport() {
        calibration = StickCalibration.read(using: Controller(transport: transport))
        transport.close()
    } else {
        Log.warn("USB bulk interface not available, using default stick calibration")
    }
    Log.debug("calibration left=\(calibration.left) right=\(calibration.right)")
    let injector = EventInjector()
    injector.dryRun = dryRun
    let bridge = KBMBridge(profile: profile, calibration: calibration, injector: injector)
    bridge.onPauseChange = { paused in
        Log.info(paused ? "bridge paused" : "bridge resumed")
        NSSound.beep()
        if paused { Thread.sleep(forTimeInterval: 0.25); NSSound.beep() }
    }
    let source = HIDInputSource(exclusive: arguments.flags.contains("--exclusive"),
                                onAttach: { Log.info("controller attached: \($0)") },
                                onDetach: { _ in Log.info("controller detached, releasing keys"); bridge.releaseAll() },
                                onState: { bridge.handle($0) })
    do { try source.start() } catch { fail("\(error)") }
    let combo = profile.pauseCombo.map(\.name).joined(separator: "+")
    Log.info("kbm bridge running, profile '\(name)'\(dryRun ? " (dry run)" : ""); hold \(combo.isEmpty ? "nothing" : combo) to pause, Ctrl+C to stop")
    installSignalHandlers {
        bridge.releaseAll()
        source.stop()
        Log.info("stopped")
        exit(0)
    }
    dispatchMain()
}

nonisolated(unsafe) var autoWake: AutoWakeService?

func daemonCommand(_ arguments: Arguments) {
    let service = AutoWakeService(variant: variant(from: arguments),
                                  format: reportFormat(from: arguments),
                                  playerLED: arguments.values["--led"].flatMap(Int.init),
                                  holdInterface: arguments.flags.contains("--hold"))
    do { try service.start() } catch { fail("\(error)") }
    autoWake = service
    dispatchMain()
}

let arguments = Arguments(Array(CommandLine.arguments.dropFirst()))
Log.verbose = arguments.flags.contains("-v") || arguments.flags.contains("--verbose")

switch arguments.command {
case "wake": wakeCommand(arguments)
case "daemon": daemonCommand(arguments)
case "list": listCommand()
case "info": infoCommand()
case "monitor": monitorCommand(arguments)
case "led": ledCommand(arguments)
case "flash": flashCommand(arguments)
case "send": sendCommand(arguments)
case "steam-mapping": print(SteamMapping.config)
case "format": formatCommand(arguments)
case "reset": resetCommand()
case "sample": sampleCommand(arguments)
case "kbm": kbmCommand(arguments)
default: print(usage)
}
