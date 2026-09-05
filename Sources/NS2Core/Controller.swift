import Foundation

public struct CommandResult: Sendable {
    public let command: BulkCommand
    public let reply: [UInt8]
    public let error: String?
}

public final class Controller {
    public let transport: BulkTransport
    public var interCommandDelay: TimeInterval = 0.05
    public var replyTimeout: TimeInterval = 0.15

    public init(transport: BulkTransport) {
        self.transport = transport
    }

    public var info: USBDeviceInfo { transport.info }

    @discardableResult
    public func execute(_ command: BulkCommand) -> CommandResult {
        do {
            try transport.send(command.bytes)
            var reply: [UInt8] = []
            for _ in 0..<4 {
                reply = try transport.receive(maxLength: 64, timeout: replyTimeout)
                if reply.isEmpty || (reply.count >= 4 && reply[0] == command.commandID && reply[3] == command.subcommand) { break }
                Log.debug("\(command.name): discarding stale reply \(reply.hexString)")
            }
            Log.debug("\(command.name): sent \(command.bytes.hexString) -> reply \(reply.isEmpty ? "(none)" : reply.hexString)")
            return CommandResult(command: command, reply: reply, error: nil)
        } catch {
            Log.debug("\(command.name): \(error)")
            return CommandResult(command: command, reply: [], error: String(describing: error))
        }
    }

    @discardableResult
    public func wake(variant: WakeUpSequence.Variant = .sdl, format: WakeUpSequence.InputReportFormat = .hid) -> [CommandResult] {
        var results: [CommandResult] = []
        for command in WakeUpSequence.commands(for: variant, format: format) {
            results.append(execute(command))
            Thread.sleep(forTimeInterval: interCommandDelay)
        }
        return results
    }

    @discardableResult
    public func setPlayerLED(_ player: Int) -> CommandResult {
        execute(WakeUpSequence.playerLED(player: player))
    }

    @discardableResult
    public func setInputReportFormat(_ format: WakeUpSequence.InputReportFormat) -> CommandResult {
        execute(WakeUpSequence.setInputReportFormat(format))
    }

    public func reset() {
        try? transport.send(WakeUpSequence.reset.bytes)
    }

    public func readFlash(address: UInt32) throws -> [UInt8] {
        try transport.send(WakeUpSequence.flashRead(address: address).bytes)
        let reply = try transport.receive(maxLength: 0x50, timeout: 0.5)
        guard reply.count > 0x10 else { return reply }
        return Array(reply[0x10...])
    }
}
