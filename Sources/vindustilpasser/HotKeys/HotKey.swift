import AppKit
import Carbon

struct HotKeyModifiers: OptionSet, Hashable, Codable {
    let rawValue: UInt32
    init(rawValue: UInt32) { self.rawValue = rawValue }
    static let command = Self(rawValue: 1 << 0)
    static let option = Self(rawValue: 1 << 1)
    static let control = Self(rawValue: 1 << 2)
    static let shift = Self(rawValue: 1 << 3)

    var carbon: UInt32 {
        (contains(.command) ? UInt32(cmdKey) : 0)
        | (contains(.option) ? UInt32(optionKey) : 0)
        | (contains(.control) ? UInt32(controlKey) : 0)
        | (contains(.shift) ? UInt32(shiftKey) : 0)
    }

    init(flags: NSEvent.ModifierFlags) {
        var value: Self = []
        if flags.contains(.command) { value.insert(.command) }
        if flags.contains(.option) { value.insert(.option) }
        if flags.contains(.control) { value.insert(.control) }
        if flags.contains(.shift) { value.insert(.shift) }
        self = value
    }

    init(from decoder: Decoder) throws {
        let values = try [String](from: decoder)
        self = []
        for value in values {
            switch value {
            case "command": insert(.command)
            case "option": insert(.option)
            case "control": insert(.control)
            case "shift": insert(.shift)
            default: throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown modifier"))
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var values: [String] = []
        if contains(.command) { values.append("command") }
        if contains(.option) { values.append("option") }
        if contains(.control) { values.append("control") }
        if contains(.shift) { values.append("shift") }
        try values.encode(to: encoder)
    }
}

struct HotKey: Codable, Hashable {
    var keyCode: UInt32
    var modifiers: HotKeyModifiers
    var displayKey: String?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.keyCode == rhs.keyCode && lhs.modifiers == rhs.modifiers
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(keyCode)
        hasher.combine(modifiers)
    }

    var isGlobalValid: Bool {
        !modifiers.isEmpty || Self.functionKeys.contains(keyCode)
    }

    var isLocalValid: Bool {
        !Self.reservedKeys.contains(keyCode)
            && !(modifiers.contains(.command) && (keyCode == UInt32(kVK_ANSI_Comma) || keyCode == UInt32(kVK_ANSI_Q)))
    }

    var label: String {
        let prefix = (modifiers.contains(.control) ? "⌃" : "")
            + (modifiers.contains(.option) ? "⌥" : "")
            + (modifiers.contains(.shift) ? "⇧" : "")
            + (modifiers.contains(.command) ? "⌘" : "")
        return prefix + (displayKey ?? "Key \(keyCode)")
    }

    static let functionKeys: Set<UInt32> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20
    ].map(UInt32.init).reduce(into: Set<UInt32>()) { $0.insert($1) }
    static let reservedKeys: Set<UInt32> = [kVK_Escape, kVK_Return, kVK_ANSI_KeypadEnter, kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow].map(UInt32.init).reduce(into: Set<UInt32>()) { $0.insert($1) }
}
