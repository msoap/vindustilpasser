import AppKit
import Carbon

@MainActor
final class PresetTableView: NSTableView {
    var onEdit: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if (event.keyCode == UInt16(kVK_Return) || event.keyCode == UInt16(kVK_ANSI_KeypadEnter)),
           event.modifierFlags.intersection([.command, .control, .option]) == [],
           selectedRow >= 0 {
            onEdit?()
            return
        }
        super.keyDown(with: event)
    }
}
