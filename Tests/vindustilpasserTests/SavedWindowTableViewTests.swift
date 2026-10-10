import AppKit
import Carbon
import Testing

@MainActor
private final class OneSavedWindowDataSource: NSObject, NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { 1 }
}

struct SavedWindowTableViewTests {
    @Test @MainActor func backspaceDeletesSelectedSavedWindow() throws {
        let table = SavedWindowTableView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        let dataSource = OneSavedWindowDataSource()
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Window")))
        table.dataSource = dataSource
        table.reloadData()
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)

        var deleteCount = 0
        table.onDelete = { deleteCount += 1 }
        let backspace = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                     windowNumber: 0, context: nil, characters: "\u{7f}",
                                                     charactersIgnoringModifiers: "\u{7f}", isARepeat: false,
                                                     keyCode: UInt16(kVK_Delete)))
        table.keyDown(with: backspace)
        #expect(deleteCount == 1)

        table.deselectAll(nil)
        table.keyDown(with: backspace)
        #expect(deleteCount == 1)
    }
}
