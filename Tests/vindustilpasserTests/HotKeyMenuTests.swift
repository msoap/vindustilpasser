import AppKit
import Carbon
import Testing

struct HotKeyMenuTests {
    @Test func functionKeyUsesAppKitEquivalent() {
        let key = HotKey(keyCode: UInt32(kVK_F11), modifiers: [.command], displayKey: "F11")
        #expect(key.menuKeyEquivalent == "\u{F70E}")
        #expect(key.menuModifierMask == .command)
    }

    @Test func recordedKeyAndModifiersAppearInMenu() {
        let key = HotKey(keyCode: UInt32(kVK_ANSI_A), modifiers: [.control, .option, .shift], displayKey: "A")
        #expect(key.menuKeyEquivalent == "a")
        #expect(key.menuModifierMask == [.control, .option, .shift])
    }

    @Test func arrowUsesAppKitEquivalent() {
        let key = HotKey(keyCode: UInt32(kVK_LeftArrow), modifiers: [.command], displayKey: "←")
        #expect(key.menuKeyEquivalent == "\u{F702}")
    }
}
