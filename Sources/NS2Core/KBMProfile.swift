import Foundation
import Carbon.HIToolbox
import CoreGraphics

public enum KeyBinding: Equatable, Sendable {
    case key(CGKeyCode)
    case mouse(CGMouseButton, number: Int64)
    case scroll(Int32)

    public var modifierFlag: CGEventFlags? {
        guard case let .key(code) = self else { return nil }
        return KeyBinding.modifierFlags(forKeyCode: code)
    }

    public static func modifierFlags(forKeyCode code: CGKeyCode) -> CGEventFlags? {
        let device: UInt64
        let mask: CGEventFlags
        switch Int(code) {
        case kVK_Shift: (mask, device) = (.maskShift, 0x0002)
        case kVK_RightShift: (mask, device) = (.maskShift, 0x0004)
        case kVK_Control: (mask, device) = (.maskControl, 0x0001)
        case kVK_RightControl: (mask, device) = (.maskControl, 0x2000)
        case kVK_Option: (mask, device) = (.maskAlternate, 0x0020)
        case kVK_RightOption: (mask, device) = (.maskAlternate, 0x0040)
        case kVK_Command: (mask, device) = (.maskCommand, 0x0008)
        case kVK_RightCommand: (mask, device) = (.maskCommand, 0x0010)
        default: return nil
        }
        return CGEventFlags(rawValue: mask.rawValue | device)
    }
}

public enum KeyTable {
    static let named: [String: Int] = [
        "space": kVK_Space, "return": kVK_Return, "enter": kVK_Return, "escape": kVK_Escape, "esc": kVK_Escape,
        "tab": kVK_Tab, "backspace": kVK_Delete, "delete": kVK_ForwardDelete, "caps_lock": kVK_CapsLock,
        "left_shift": kVK_Shift, "shift": kVK_Shift, "right_shift": kVK_RightShift,
        "left_ctrl": kVK_Control, "ctrl": kVK_Control, "right_ctrl": kVK_RightControl,
        "left_alt": kVK_Option, "alt": kVK_Option, "option": kVK_Option, "right_alt": kVK_RightOption,
        "left_cmd": kVK_Command, "cmd": kVK_Command, "right_cmd": kVK_RightCommand,
        "up": kVK_UpArrow, "down": kVK_DownArrow, "left": kVK_LeftArrow, "right": kVK_RightArrow,
        "home": kVK_Home, "end": kVK_End, "page_up": kVK_PageUp, "page_down": kVK_PageDown,
        "minus": kVK_ANSI_Minus, "equal": kVK_ANSI_Equal, "comma": kVK_ANSI_Comma, "period": kVK_ANSI_Period,
        "slash": kVK_ANSI_Slash, "semicolon": kVK_ANSI_Semicolon, "quote": kVK_ANSI_Quote,
        "bracket_left": kVK_ANSI_LeftBracket, "bracket_right": kVK_ANSI_RightBracket,
        "backslash": kVK_ANSI_Backslash, "grave": kVK_ANSI_Grave,
        "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4, "f5": kVK_F5, "f6": kVK_F6, "f7": kVK_F7,
        "f8": kVK_F8, "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12, "f13": kVK_F13,
        "f14": kVK_F14, "f15": kVK_F15, "f16": kVK_F16, "f17": kVK_F17, "f18": kVK_F18, "f19": kVK_F19, "f20": kVK_F20,
    ]

    static let letters: [Character: Int] = [
        "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E, "f": kVK_ANSI_F,
        "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
        "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R,
        "s": kVK_ANSI_S, "t": kVK_ANSI_T, "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
        "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
        "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
    ]

    static let canonicalOrder: [String] = [
        "space", "return", "escape", "tab", "backspace", "delete", "caps_lock",
        "left_shift", "right_shift", "left_ctrl", "right_ctrl", "left_alt", "right_alt", "left_cmd", "right_cmd",
        "up", "down", "left", "right", "home", "end", "page_up", "page_down",
        "minus", "equal", "comma", "period", "slash", "semicolon", "quote", "bracket_left", "bracket_right", "backslash", "grave",
        "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12", "f13", "f14", "f15", "f16", "f17", "f18", "f19", "f20",
    ]

    static let codeNames: [Int: String] = {
        var table: [Int: String] = [:]
        for (character, code) in letters { table[code] = String(character) }
        for name in canonicalOrder { if let code = named[name], table[code] == nil { table[code] = name } }
        return table
    }()

    public static let allNames: [String] = letters.keys.map(String.init).sorted() + canonicalOrder
        + ["mouse_left", "mouse_right", "mouse_middle", "mouse_4", "mouse_5", "scroll_up", "scroll_down"]

    public static func name(for binding: KeyBinding) -> String? {
        switch binding {
        case let .key(code): return codeNames[Int(code)]
        case let .mouse(_, number):
            switch number {
            case 0: return "mouse_left"
            case 1: return "mouse_right"
            case 2: return "mouse_middle"
            case 3: return "mouse_4"
            default: return "mouse_5"
            }
        case let .scroll(lines): return lines > 0 ? "scroll_up" : "scroll_down"
        }
    }

    public static func name(forKeyCode code: Int) -> String? { codeNames[code] }

    public static func binding(for rawName: String) -> KeyBinding? {
        let name = rawName.lowercased().trimmingCharacters(in: .whitespaces)
        switch name {
        case "mouse_left": return .mouse(.left, number: 0)
        case "mouse_right": return .mouse(.right, number: 1)
        case "mouse_middle": return .mouse(.center, number: 2)
        case "mouse_4": return .mouse(.center, number: 3)
        case "mouse_5": return .mouse(.center, number: 4)
        case "scroll_up": return .scroll(1)
        case "scroll_down": return .scroll(-1)
        default: break
        }
        if name.count == 1, let code = letters[name.first!] { return .key(CGKeyCode(code)) }
        if let code = named[name] { return .key(CGKeyCode(code)) }
        return nil
    }
}

public enum StickMode: String, Codable, Sendable {
    case keys
    case mouse
    case none
}

public struct StickConfig: Codable, Equatable, Sendable {
    public var mode: StickMode
    public var threshold: Double?
    public var up: String?
    public var down: String?
    public var left: String?
    public var right: String?
    public var sensitivity: Double?
    public var curve: Double?
    public var invertY: Bool?

    enum CodingKeys: String, CodingKey {
        case mode, threshold, up, down, left, right, sensitivity, curve
        case invertY = "invert_y"
    }
}

public struct KBMProfile: Codable, Equatable, Sendable {
    public var deadzone: Double
    public var leftStick: StickConfig
    public var rightStick: StickConfig
    public var buttons: [String: String?]
    public var pauseCombo: [String]
    public var pauseHoldSeconds: Double?

    enum CodingKeys: String, CodingKey {
        case deadzone, buttons
        case leftStick = "left_stick"
        case rightStick = "right_stick"
        case pauseCombo = "pause_combo"
        case pauseHoldSeconds = "pause_hold_seconds"
    }

    public static let template = """
    {
      "deadzone": 0.15,
      "left_stick":  { "mode": "keys",  "threshold": 0.5, "up": "w", "down": "s", "left": "a", "right": "d" },
      "right_stick": { "mode": "mouse", "sensitivity": 1200, "curve": 1.5, "invert_y": false },
      "buttons": {
        "a": "space", "b": "left_ctrl", "x": "e", "y": "r",
        "l": "mouse_right", "r": "mouse_left", "zl": "q", "zr": "left_shift",
        "minus": "tab", "plus": "escape", "ls": "left_shift", "rs": "mouse_middle",
        "home": null, "capture": "f12", "c": null,
        "dpad_up": "1", "dpad_down": "3", "dpad_left": "2", "dpad_right": "4",
        "gl": "f", "gr": "g"
      },
      "pause_combo": ["home"],
      "pause_hold_seconds": 1.0
    }

    """

    public static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ns2controller/profiles", isDirectory: true)
    }

    public static func url(for name: String) -> URL {
        directory.appendingPathComponent("\(name).json")
    }

    public static func list() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasSuffix(".json") }.map { String($0.dropLast(5)) }.sorted()
    }

    @discardableResult
    public static func writeTemplate(name: String, overwrite: Bool = false) throws -> URL {
        let url = url(for: name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !overwrite, FileManager.default.fileExists(atPath: url.path) { return url }
        try template.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    public static func save(_ profile: KBMProfile, name: String) throws -> URL {
        let url = url(for: name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(profile).write(to: url)
        return url
    }

    public static func delete(name: String) throws {
        try FileManager.default.removeItem(at: url(for: name))
    }

    public static func load(name: String) throws -> KBMProfile {
        let url = url(for: name)
        if !FileManager.default.fileExists(atPath: url.path) {
            if name == "default" {
                try writeTemplate(name: name)
                Log.info("created default profile at \(url.path)")
            } else {
                throw NS2Error.profile("profile '\(name)' not found at \(url.path); create it with: ns2ctl kbm --init-profile \(name)")
            }
        }
        return try parse(Data(contentsOf: url))
    }

    public static func parse(_ data: Data) throws -> KBMProfile {
        do {
            return try JSONDecoder().decode(KBMProfile.self, from: data)
        } catch {
            throw NS2Error.profile("invalid profile JSON: \(error)")
        }
    }

    public func resolved() throws -> ResolvedProfile {
        try ResolvedProfile(profile: self)
    }
}

public struct ResolvedStick: Sendable {
    public enum Mode: Sendable {
        case none
        case keys(threshold: Double, up: KeyBinding?, down: KeyBinding?, left: KeyBinding?, right: KeyBinding?)
        case mouse(sensitivity: Double, curve: Double, invertY: Bool)
    }
    public var mode: Mode
}

public struct ResolvedProfile: Sendable {
    public var deadzone: Double
    public var left: ResolvedStick
    public var right: ResolvedStick
    public var bindings: [ProController2Button: KeyBinding]
    public var pauseCombo: Set<ProController2Button>
    public var pauseHoldSeconds: Double

    init(profile: KBMProfile) throws {
        deadzone = max(0, min(0.9, profile.deadzone))
        left = try Self.resolve(profile.leftStick, label: "left_stick")
        right = try Self.resolve(profile.rightStick, label: "right_stick")
        var bindings: [ProController2Button: KeyBinding] = [:]
        for (key, value) in profile.buttons {
            guard let button = ProController2Button.allCases.first(where: { $0.profileKey == key }) else {
                throw NS2Error.profile("unknown button '\(key)' in buttons; valid: \(ProController2Button.allCases.map(\.profileKey).joined(separator: ", "))")
            }
            guard let value else { continue }
            bindings[button] = try Self.binding(value, context: "buttons.\(key)")
        }
        self.bindings = bindings
        pauseCombo = Set(try profile.pauseCombo.map { key in
            guard let button = ProController2Button.allCases.first(where: { $0.profileKey == key }) else {
                throw NS2Error.profile("unknown button '\(key)' in pause_combo")
            }
            return button
        })
        pauseHoldSeconds = max(0.2, profile.pauseHoldSeconds ?? 1.0)
    }

    static func binding(_ name: String, context: String) throws -> KeyBinding {
        guard let binding = KeyTable.binding(for: name) else {
            throw NS2Error.profile("unknown key '\(name)' in \(context)")
        }
        return binding
    }

    static func resolve(_ config: StickConfig, label: String) throws -> ResolvedStick {
        switch config.mode {
        case .none:
            return ResolvedStick(mode: .none)
        case .keys:
            let threshold = max(0.1, min(0.9, config.threshold ?? 0.5))
            func bind(_ name: String?, _ direction: String) throws -> KeyBinding? {
                guard let name else { return nil }
                return try binding(name, context: "\(label).\(direction)")
            }
            return ResolvedStick(mode: .keys(threshold: threshold, up: try bind(config.up, "up"), down: try bind(config.down, "down"),
                                             left: try bind(config.left, "left"), right: try bind(config.right, "right")))
        case .mouse:
            return ResolvedStick(mode: .mouse(sensitivity: max(1, config.sensitivity ?? 1200),
                                              curve: max(0.5, min(3, config.curve ?? 1.5)),
                                              invertY: config.invertY ?? false))
        }
    }
}

public extension ProController2Button {
    var profileKey: String {
        switch self {
        case .b: return "b"
        case .a: return "a"
        case .y: return "y"
        case .x: return "x"
        case .r: return "r"
        case .zr: return "zr"
        case .plus: return "plus"
        case .rightStick: return "rs"
        case .dpadDown: return "dpad_down"
        case .dpadRight: return "dpad_right"
        case .dpadLeft: return "dpad_left"
        case .dpadUp: return "dpad_up"
        case .l: return "l"
        case .zl: return "zl"
        case .minus: return "minus"
        case .leftStick: return "ls"
        case .home: return "home"
        case .capture: return "capture"
        case .gr: return "gr"
        case .gl: return "gl"
        case .c: return "c"
        }
    }
}
