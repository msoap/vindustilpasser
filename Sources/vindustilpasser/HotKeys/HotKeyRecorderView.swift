import AppKit
import Carbon

@MainActor
final class HotKeyRecorderView: NSButton {
    var hotKey: HotKey? { didSet { updateTitle() } }
    var onChange: ((HotKey?) -> Void)?
    private var recording = false

    override var acceptsFirstResponder: Bool { true }

    override init(frame: CGRect) {
        super.init(frame: frame)
        bezelStyle = .rounded
        target = self
        action = #selector(beginRecording)
        setAccessibilityLabel("Shortcut recorder")
        updateTitle()
    }

    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    @objc private func beginRecording() {
        recording = true
        title = "Press shortcut…"
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        let code = UInt32(event.keyCode)
        if code == UInt32(kVK_Escape) { recording = false; updateTitle(); return }
        if code == UInt32(kVK_Delete) || code == UInt32(kVK_ForwardDelete) {
            recording = false
            hotKey = nil
            onChange?(nil)
            return
        }
        let modifiers = HotKeyModifiers(flags: event.modifierFlags.intersection(.deviceIndependentFlagsMask))
        let display: String
        let arrowKeys: [UInt32: String] = [UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→",
                                           UInt32(kVK_UpArrow): "↑", UInt32(kVK_DownArrow): "↓"]
        if let arrow = arrowKeys[code] {
            display = arrow
        } else if let functionIndex = (1...20).first(where: { index in
            let codes: [Int] = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                                kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
            return UInt32(codes[index - 1]) == code
        }) {
            display = "F\(functionIndex)"
        } else {
            display = event.charactersIgnoringModifiers?.uppercased() ?? "Key \(code)"
        }
        let candidate = HotKey(keyCode: code, modifiers: modifiers, displayKey: display)
        recording = false
        hotKey = candidate
        onChange?(candidate)
    }

    override func resignFirstResponder() -> Bool {
        recording = false
        updateTitle()
        return super.resignFirstResponder()
    }

    private func updateTitle() { title = hotKey?.label ?? "Record…" }
}
