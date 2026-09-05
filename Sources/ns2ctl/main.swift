import Foundation
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
               ["--variant", "--led", "--hold", "--format"].contains(arg) {
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

func daemonCommand(_ arguments: Arguments) {
    let daemon = Daemon(variant: variant(from: arguments),
                        format: reportFormat(from: arguments),
                        playerLED: arguments.values["--led"].flatMap(Int.init),
                        holdInterface: arguments.flags.contains("--hold"))
    do { try daemon.start() } catch { fail("\(error)") }
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
default: print(usage)
}
