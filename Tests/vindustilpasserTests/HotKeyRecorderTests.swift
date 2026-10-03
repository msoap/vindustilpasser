import AppKit
import Carbon
import Testing

struct HotKeyRecorderTests {
    @Test @MainActor func recordsNewAndReplacementLocalKeys() throws {
        let recorder = HotKeyRecorderView(frame: CGRect(x: 0, y: 0, width: 140, height: 28))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 200, height: 80),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView?.addSubview(recorder)
        var observed: HotKey?
        recorder.onChange = { observed = $0 }
        recorder.performClick(nil)
        #expect(recorder.title == "Press shortcut…")
        let first = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                   windowNumber: 0, context: nil, characters: "3", charactersIgnoringModifiers: "3",
                                                   isARepeat: false, keyCode: UInt16(kVK_ANSI_3)))
        recorder.keyDown(with: first)
        #expect(recorder.hotKey?.keyCode == UInt32(kVK_ANSI_3))
        #expect(recorder.title == "3")
        #expect(observed == recorder.hotKey)

        recorder.hotKey = HotKey(keyCode: UInt32(kVK_ANSI_1), modifiers: [], displayKey: "1")
        recorder.performClick(nil)
        let replacement = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                         windowNumber: 0, context: nil, characters: "2", charactersIgnoringModifiers: "2",
                                                         isARepeat: false, keyCode: UInt16(kVK_ANSI_2)))
        recorder.keyDown(with: replacement)
        #expect(recorder.hotKey?.keyCode == UInt32(kVK_ANSI_2))
        #expect(recorder.title == "2")
        #expect(observed == recorder.hotKey)

        recorder.performClick(nil)
        let commandLeft = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0,
                                                         windowNumber: 0, context: nil, characters: "\u{F702}", charactersIgnoringModifiers: "\u{F702}",
                                                         isARepeat: false, keyCode: UInt16(kVK_LeftArrow)))
        recorder.keyDown(with: commandLeft)
        #expect(recorder.hotKey?.keyCode == UInt32(kVK_LeftArrow))
        #expect(recorder.hotKey?.modifiers == [.command])
        #expect(recorder.title == "⌘←")
        #expect(observed == recorder.hotKey)

        recorder.performClick(nil)
        let commandRight = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0,
                                                          windowNumber: 0, context: nil, characters: "\u{F703}", charactersIgnoringModifiers: "\u{F703}",
                                                          isARepeat: false, keyCode: UInt16(kVK_RightArrow)))
        recorder.keyDown(with: commandRight)
        #expect(recorder.hotKey?.keyCode == UInt32(kVK_RightArrow))
        #expect(recorder.hotKey?.modifiers == [.command])
        #expect(recorder.title == "⌘→")
        #expect(observed == recorder.hotKey)

        recorder.performClick(nil)
        let optionLeft = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.option], timestamp: 0,
                                                        windowNumber: 0, context: nil, characters: "\u{F702}", charactersIgnoringModifiers: "\u{F702}",
                                                        isARepeat: false, keyCode: UInt16(kVK_LeftArrow)))
        recorder.keyDown(with: optionLeft)
        #expect(recorder.title == "⌥←")

        recorder.performClick(nil)
        let commandShiftRight = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .shift], timestamp: 0,
                                                               windowNumber: 0, context: nil, characters: "\u{F703}", charactersIgnoringModifiers: "\u{F703}",
                                                               isARepeat: false, keyCode: UInt16(kVK_RightArrow)))
        recorder.keyDown(with: commandShiftRight)
        #expect(recorder.title == "⇧⌘→")
    }
}
