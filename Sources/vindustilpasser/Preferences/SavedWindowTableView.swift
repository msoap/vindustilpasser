import AppKit
import Carbon

@MainActor
final class SavedWindowTableView: NSTableView {
    var onDelete: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Delete),
           event.modifierFlags.intersection([.command, .control, .option]) == [],
           selectedRow >= 0 {
            onDelete?()
            return
        }
        super.keyDown(with: event)
    }
}
