import AppKit
import Carbon
import Testing

@MainActor
private final class OnePresetDataSource: NSObject, NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { 1 }
}

struct PresetTableViewTests {
    @Test @MainActor func returnAndKeypadEnterEditSelectedPreset() throws {
        let table = PresetTableView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        let dataSource = OnePresetDataSource()
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Name")))
        table.dataSource = dataSource
        table.reloadData()
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        #expect(table.selectedRow == 0)

        var editCount = 0
        table.onEdit = { editCount += 1 }
        for (keyCode, characters) in [(kVK_Return, "\r"), (kVK_ANSI_KeypadEnter, "\u{3}")] {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                      windowNumber: 0, context: nil, characters: characters,
                                                      charactersIgnoringModifiers: characters, isARepeat: false,
                                                      keyCode: UInt16(keyCode)))
            table.keyDown(with: event)
        }
        #expect(editCount == 2)
    }
}
