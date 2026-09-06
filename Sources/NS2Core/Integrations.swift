import Foundation

public enum SteamIntegration {
    public enum Status: Equatable, Sendable {
        case steamNotFound
        case notInstalled
        case installed
        case outdated
    }

    public static let bindKey = "SDL_GamepadBind"
    public static let steamBundleIdentifier = "com.valvesoftware.steam"

    public static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Steam/config/config.vdf")
    }

    public static var mappingValue: String {
        SteamMapping.config.split(separator: "\n").map { $0.replacingOccurrences(of: "\"", with: "'") }.joined(separator: "\\n")
    }

    public static func status() -> Status {
        guard let text = try? String(contentsOf: configURL, encoding: .utf8) else { return .steamNotFound }
        guard let value = currentValue(in: text) else { return .notInstalled }
        let primary = SteamMapping.line(guid: SteamMapping.guids[0]).replacingOccurrences(of: "\"", with: "'")
        return value.contains(primary) ? .installed : .outdated
    }

    static func currentValue(in text: String) -> String? {
        guard let span = bindingSpans(in: text).first else { return nil }
        let line = text[span]
        guard let key = line.range(of: "\"\(bindKey)\""), let start = line[key.upperBound...].firstIndex(of: "\""),
              let end = line.lastIndex(of: "\""), end > start else { return nil }
        return String(line[line.index(after: start)..<end])
    }

    static func bindingSpans(in text: String) -> [Range<String.Index>] {
        var spans: [Range<String.Index>] = []
        var searchStart = text.startIndex
        let key = "\"\(bindKey)\""
        while let found = text.range(of: key, range: searchStart..<text.endIndex) {
            let lineStart = text[..<found.lowerBound].lastIndex(of: "\n").map(text.index(after:)) ?? text.startIndex
            guard let quote = text[found.upperBound...].firstIndex(of: "\"") else { break }
            var cursor = text.index(after: quote)
            while cursor < text.endIndex {
                if text[cursor] == "\\" {
                    cursor = text.index(cursor, offsetBy: 2, limitedBy: text.endIndex) ?? text.endIndex
                    continue
                }
                if text[cursor] == "\"" { break }
                cursor = text.index(after: cursor)
            }
            let lineEnd = text[cursor...].firstIndex(of: "\n").map(text.index(after:)) ?? text.endIndex
            spans.append(lineStart..<lineEnd)
            searchStart = lineEnd
        }
        return spans
    }

    public static func patched(_ text: String) throws -> String {
        var result = text
        for span in bindingSpans(in: text).reversed() { result.removeSubrange(span) }
        let head = "\"InstallConfigStore\"\n{\n"
        guard result.hasPrefix(head) else { throw NS2Error.profile("unexpected config.vdf format, nothing changed") }
        return head + "\t\"\(bindKey)\"\t\t\"\(mappingValue)\"\n" + result.dropFirst(head.count)
    }

    @discardableResult
    public static func install() throws -> URL {
        let url = configURL
        let text = try String(contentsOf: url, encoding: .utf8)
        let backup = url.deletingLastPathComponent().appendingPathComponent("config.vdf.bak-ns2-\(Self.stamp())")
        try FileManager.default.copyItem(at: url, to: backup)
        try patched(text).write(to: url, atomically: true, encoding: .utf8)
        Log.info("Steam mapping installed into config.vdf (backup: \(backup.lastPathComponent))")
        return backup
    }

    static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

public enum CrossOverIntegration {
    public static let environmentKey = "SDL_GAMECONTROLLERCONFIG"

    public static var bottlesURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/CrossOver/Bottles")
    }

    public static var wineBinary: URL? {
        for app in ["/Applications/CrossOver.app", "/Applications/CrossOver Preview.app"] {
            let url = URL(fileURLWithPath: "\(app)/Contents/SharedSupport/CrossOver/bin/wine")
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        return nil
    }

    public static var isAvailable: Bool { wineBinary != nil }

    public static var mappingLine: String { SteamMapping.line(guid: SteamMapping.guids[0]) }

    public static func bottles() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: bottlesURL.path)) ?? [])
            .filter { FileManager.default.fileExists(atPath: confURL(bottle: $0).path) }
            .sorted()
    }

    public static func confURL(bottle: String) -> URL {
        bottlesURL.appendingPathComponent(bottle).appendingPathComponent("cxbottle.conf")
    }

    public static func isInstalled(bottle: String) -> Bool {
        guard let text = try? String(contentsOf: confURL(bottle: bottle), encoding: .utf8) else { return false }
        return text.contains("\"\(environmentKey)\" = \"\(mappingLine)\"")
    }

    public static func patched(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n").filter { !$0.hasPrefix("\"\(environmentKey)\" = ") }
        let marker = "[EnvironmentVariables]"
        let entry = "\"\(environmentKey)\" = \"\(mappingLine)\""
        if let index = lines.firstIndex(of: marker) {
            lines.insert(entry, at: index + 1)
        } else {
            if lines.last?.isEmpty == false { lines.append("") }
            lines.append(contentsOf: [marker, entry])
        }
        return lines.joined(separator: "\n")
    }

    @discardableResult
    public static func install(bottle: String) throws -> URL {
        let url = confURL(bottle: bottle)
        let text = try String(contentsOf: url, encoding: .utf8)
        let backup = url.deletingLastPathComponent().appendingPathComponent("cxbottle.conf.bak-ns2-\(SteamIntegration.stamp())")
        try FileManager.default.copyItem(at: url, to: backup)
        try patched(text).write(to: url, atomically: true, encoding: .utf8)
        Log.info("CrossOver mapping written to \(url.path)")
        return backup
    }

    public static func removeWinebusMapKey(bottle: String, completion: @escaping @Sendable (Bool) -> Void) {
        guard let wine = wineBinary else { completion(false); return }
        DispatchQueue.global().async {
            let process = Process()
            process.executableURL = wine
            process.arguments = ["--bottle", bottle, "reg", "delete", #"HKLM\System\CurrentControlSet\Services\winebus\map"#, "/f"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                Log.info("winebus map key cleanup in bottle '\(bottle)' finished (status \(process.terminationStatus))")
                completion(true)
            } catch {
                Log.warn("could not run wine for bottle '\(bottle)': \(error)")
                completion(false)
            }
        }
    }
}
