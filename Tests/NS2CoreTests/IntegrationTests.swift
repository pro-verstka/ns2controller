import Foundation
import Testing
@testable import NS2Core

@Suite struct SteamIntegrationTests {
    @Test func replacesMultilineBindingAndInsertsOnce() throws {
        let config = """
        "InstallConfigStore"
        {
        \t"Software"
        \t{
        \t}
        \t"SDL_GamepadBind"\t\t"030000007e0500006920000001000000,Old,a:b1,
        stray line
        030000007e0500006920000001020000,Old2,a:b1,platform:Mac OS X,"
        \t"Other"\t\t"x"
        }
        """
        let patched = try SteamIntegration.patched(config)
        #expect(patched.components(separatedBy: "\"SDL_GamepadBind\"").count == 2)
        #expect(!patched.contains("stray line"))
        #expect(patched.contains("\t\"Other\"\t\t\"x\""))
        #expect(patched.hasPrefix("\"InstallConfigStore\"\n{\n\t\"SDL_GamepadBind\"\t\t\"030002697e05"))
        #expect(SteamIntegration.currentValue(in: patched) == SteamIntegration.mappingValue)
    }

    @Test func rejectsUnexpectedFormat() {
        #expect(throws: NS2Error.self) { try SteamIntegration.patched("nope") }
    }
}

@Suite struct CrossOverIntegrationTests {
    @Test func insertsEnvironmentVariableAfterSection() {
        let conf = "[Bottle]\n\"Name\" = \"Steam\"\n\n[EnvironmentVariables]\n\"WINEMSYNC\" = \"1\"\n\"SDL_GAMECONTROLLERCONFIG\" = \"old\"\n"
        let patched = CrossOverIntegration.patched(conf)
        let lines = patched.components(separatedBy: "\n")
        let section = lines.firstIndex(of: "[EnvironmentVariables]")!
        #expect(lines[section + 1].hasPrefix("\"SDL_GAMECONTROLLERCONFIG\" = \"030002697e05"))
        #expect(!patched.contains("\"old\""))
        #expect(patched.contains("\"WINEMSYNC\" = \"1\""))
    }

    @Test func appendsSectionWhenMissing() {
        let patched = CrossOverIntegration.patched("[Bottle]\n\"Name\" = \"X\"\n")
        #expect(patched.contains("\n[EnvironmentVariables]\n\"SDL_GAMECONTROLLERCONFIG\" = \""))
    }
}

@Suite struct ModifierFlagTests {
    @Test func leftAndRightModifiersCarryDeviceBits() {
        let left = KeyBinding.modifierFlags(forKeyCode: 56)!
        let right = KeyBinding.modifierFlags(forKeyCode: 60)!
        #expect(left.contains(.maskShift) && right.contains(.maskShift))
        #expect(left.rawValue & 0x2 != 0 && right.rawValue & 0x4 != 0)
        #expect(KeyBinding.modifierFlags(forKeyCode: 59)!.rawValue & 0x1 != 0)
        #expect(KeyBinding.modifierFlags(forKeyCode: 14) == nil)
    }
}

@Suite struct KeyTableTests {
    @Test func roundTripsNames() {
        for name in ["w", "5", "space", "left_shift", "f12", "mouse_right", "scroll_down", "return"] {
            let binding = KeyTable.binding(for: name)
            #expect(binding != nil)
            #expect(KeyTable.name(for: binding!) == name)
        }
    }
}
