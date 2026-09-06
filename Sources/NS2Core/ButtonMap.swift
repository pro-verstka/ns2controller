import Foundation

public enum ProController2Button: Int, CaseIterable, Sendable {
    case b = 1, a, y, x, r, zr, plus, rightStick, dpadDown, dpadRight, dpadLeft, dpadUp
    case l, zl, minus, leftStick, home, capture, gr, gl, c

    public var hidUsage: Int { rawValue }

    public var name: String {
        switch self {
        case .b: return "B"
        case .a: return "A"
        case .y: return "Y"
        case .x: return "X"
        case .r: return "R"
        case .zr: return "ZR"
        case .plus: return "+"
        case .rightStick: return "RS"
        case .dpadDown: return "D-pad Down"
        case .dpadRight: return "D-pad Right"
        case .dpadLeft: return "D-pad Left"
        case .dpadUp: return "D-pad Up"
        case .l: return "L"
        case .zl: return "ZL"
        case .minus: return "-"
        case .leftStick: return "LS"
        case .home: return "Home"
        case .capture: return "Capture"
        case .gr: return "GR"
        case .gl: return "GL"
        case .c: return "C"
        }
    }

    public var sdlName: String? {
        switch self {
        case .b: return "a"
        case .a: return "b"
        case .y: return "x"
        case .x: return "y"
        case .r: return "rightshoulder"
        case .zr: return "righttrigger"
        case .plus: return "start"
        case .rightStick: return "rightstick"
        case .dpadDown: return "dpdown"
        case .dpadRight: return "dpright"
        case .dpadLeft: return "dpleft"
        case .dpadUp: return "dpup"
        case .l: return "leftshoulder"
        case .zl: return "lefttrigger"
        case .minus: return "back"
        case .leftStick: return "leftstick"
        case .home: return "guide"
        case .capture: return "misc1"
        case .gr: return "paddle1"
        case .gl: return "paddle2"
        case .c: return nil
        }
    }
}

public extension ProController2Button {
    static var byProfileKey: [String: ProController2Button] {
        Dictionary(uniqueKeysWithValues: allCases.map { ($0.profileKey, $0) })
    }
}

public enum SteamMapping {
    public static let controllerName = "Nintendo Switch 2 Pro Controller"

    public static let guids: [String] = [
        "030002697e0500006920000001020000",
        "030000007e0500006920000001020000",
        "030000007e0500006920000001000000",
    ]

    public static var elements: String {
        var parts = ProController2Button.allCases.compactMap { button -> String? in
            guard let sdl = button.sdlName else { return nil }
            return "\(sdl):b\(button.hidUsage - 1)"
        }
        parts += ["leftx:a0", "lefty:a1~", "rightx:a2", "righty:a3~"]
        return parts.joined(separator: ",")
    }

    public static func line(guid: String) -> String {
        "\(guid),\(controllerName),\(elements),platform:Mac OS X,"
    }

    public static var config: String {
        guids.map(line(guid:)).joined(separator: "\n")
    }
}
