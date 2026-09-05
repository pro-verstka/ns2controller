import Foundation
import os

public enum Log {
    nonisolated(unsafe) public static var verbose = false
    private static let logger = Logger(subsystem: "com.p1rate.ns2controller", category: "ns2ctl")
    private static let stampFormatter: DateFormatter = {
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

    private static func emit(_ level: String, _ message: String) {
        print("\(stampFormatter.string(from: Date())) [\(level)] \(message)")
        fflush(stdout)
    }
}

public extension Array where Element == UInt8 {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined(separator: " ")
    }
}
