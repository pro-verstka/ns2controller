import Foundation
import os

public struct LogLine: Sendable, Identifiable {
    public let id: Int
    public let date: Date
    public let level: String
    public let message: String

    public var formatted: String {
        "\(Log.stampFormatter.string(from: date)) [\(level)] \(message)"
    }
}

public enum Log {
    nonisolated(unsafe) public static var verbose = false
    nonisolated(unsafe) public static var printToStdout = true
    nonisolated(unsafe) public static var sink: (@Sendable (LogLine) -> Void)?
    private static let logger = Logger(subsystem: "com.p1rate.ns2controller", category: "ns2ctl")
    private static let bufferLock = NSLock()
    nonisolated(unsafe) private static var buffer: [LogLine] = []
    nonisolated(unsafe) private static var nextID = 0
    public static let bufferLimit = 2000

    static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    public static func info(_ message: String) {
        emit("INFO", message)
        logger.info("\(message, privacy: .public)")
    }

    public static func warn(_ message: String) {
        emit("WARN", message)
        logger.warning("\(message, privacy: .public)")
    }

    public static func error(_ message: String) {
        emit("ERROR", message)
        logger.error("\(message, privacy: .public)")
    }

    public static func debug(_ message: String) {
        guard verbose else { return }
        emit("DEBUG", message)
        logger.debug("\(message, privacy: .public)")
    }

    public static func recent() -> [LogLine] {
        bufferLock.lock(); defer { bufferLock.unlock() }
        return buffer
    }

    private static func emit(_ level: String, _ message: String) {
        bufferLock.lock()
        let line = LogLine(id: nextID, date: Date(), level: level, message: message)
        nextID += 1
        buffer.append(line)
        if buffer.count > bufferLimit { buffer.removeFirst(buffer.count - bufferLimit) }
        bufferLock.unlock()
        if printToStdout {
            print(line.formatted)
            fflush(stdout)
        }
        sink?(line)
    }
}

public extension Array where Element == UInt8 {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined(separator: " ")
    }
}
