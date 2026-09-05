import Testing
@testable import NS2Core

@Suite struct WakeUpSequenceTests {
    @Test func allCommandsAreWellFormed() {
        for variant in WakeUpSequence.Variant.allCases {
            for command in WakeUpSequence.commands(for: variant) {
                #expect(command.isWellFormed, "\(variant): \(command.name)")
            }
        }
    }

    @Test func frameLengthFollowsHeaderByte5() {
        let command = BulkCommand.make(command: 0x0C, subcommand: 0x02, payload: [0x27, 0, 0, 0], name: "x")
        #expect(command.bytes == [0x0C, 0x91, 0x00, 0x02, 0x00, 0x04, 0x00, 0x00, 0x27, 0, 0, 0])
        #expect(command.bytes.count == command.declaredPayloadLength + BulkCommand.headerLength)
    }

    @Test func playerLEDMatchesSDLPattern() {
        #expect(WakeUpSequence.playerLED(player: 1).bytes == [0x09, 0x91, 0x00, 0x07, 0x00, 0x08, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0, 0])
        #expect(WakeUpSequence.playerLED(player: 4).bytes[8] == 0x0F)
        #expect(WakeUpSequence.playerLED(player: 9).bytes[8] == 0x01)
    }

    @Test func flashReadEncodesLittleEndianAddress() {
        let command = WakeUpSequence.flashRead(address: 0x013080)
        #expect(command.bytes.count == 16)
        #expect(Array(command.bytes[12...15]) == [0x80, 0x30, 0x01, 0x00])
    }

    @Test func inputReportFormatCommand() {
        #expect(WakeUpSequence.setInputReportFormat(.hid).bytes == [0x03, 0x91, 0x00, 0x0A, 0x00, 0x04, 0x00, 0x00, 0x09, 0, 0, 0])
        #expect(WakeUpSequence.setInputReportFormat(.vendor).bytes[8] == 0x05)
        #expect(WakeUpSequence.sdl(format: .hid).contains { $0.commandID == 0x03 && $0.subcommand == 0x0A && $0.bytes[8] == 0x09 })
    }

    @Test func resetIsNeverPartOfASequence() {
        for variant in WakeUpSequence.Variant.allCases {
            #expect(!WakeUpSequence.commands(for: variant).contains(WakeUpSequence.reset))
        }
    }

    @Test func sdlSequenceOrderIsPreserved() {
        let ids = WakeUpSequence.sdl(format: .vendor).map { ($0.commandID, $0.subcommand) }
        let expected: [(UInt8, UInt8)] = [(0x07, 0x01), (0x0C, 0x02), (0x11, 0x01), (0x0A, 0x08), (0x0C, 0x04),
                                          (0x01, 0x0C), (0x01, 0x01), (0x08, 0x02), (0x03, 0x0A), (0x03, 0x0D)]
        #expect(ids.count == expected.count)
        for (actual, wanted) in zip(ids, expected) {
            #expect(actual.0 == wanted.0 && actual.1 == wanted.1)
        }
    }
}

@Suite struct ButtonMapTests {
    @Test func twentyOneButtonsMatchDescriptor() {
        #expect(ProController2Button.allCases.count == 21)
        #expect(ProController2Button.allCases.map(\.hidUsage) == Array(1...21))
    }

    @Test func steamMappingUsesZeroBasedIndices() {
        let line = SteamMapping.line(guid: SteamMapping.guids[0])
        #expect(line.hasPrefix("030002697e0500006920000001020000,Nintendo Switch 2 Pro Controller,"))
        #expect(line.contains("a:b0,b:b1,x:b2,y:b3,"))
        #expect(line.contains("guide:b16,misc1:b17,paddle1:b18,paddle2:b19"))
        #expect(line.contains("lefty:a1~"))
        #expect(line.hasSuffix("platform:Mac OS X,"))
    }
}
