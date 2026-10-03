import AppKit
import Carbon

@MainActor
private final class PresetEditorWindow: NSWindow {
    var onEscape: (() -> Void)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == UInt16(kVK_Escape), let onEscape {
            onEscape()
            return
        }
        super.sendEvent(event)
    }
}

@MainActor
final class PresetEditorController: NSWindowController, NSWindowDelegate {
    private let nameField = NSTextField()
    private let scope = NSPopUpButton()
    private let recorder = HotKeyRecorderView()
    private let grid = GridView()
    private let fineCheckbox = NSButton(checkboxWithTitle: "Fine grid", target: nil, action: nil)
    private var preset: WindowPreset
    private let onSave: (WindowPreset) throws -> Void

    init(preset: WindowPreset, defaultGrid: AppSettings.Grid, onSave: @escaping (WindowPreset) throws -> Void) {
        self.preset = preset
        self.onSave = onSave
        let window = PresetEditorWindow(contentRect: CGRect(x: 0, y: 0, width: 460, height: 440),
                                        styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Edit Preset"
        window.center()
        super.init(window: window)
        window.delegate = self
        window.onEscape = { [weak self] in self?.dismiss(.cancel) }
        guard let content = window.contentView else { return }
        nameField.frame = CGRect(x: 110, y: 390, width: 320, height: 25)
        nameField.placeholderString = "Optional name"
        nameField.stringValue = preset.name ?? ""
        content.addSubview(label("Name", x: 20, y: 393))
        content.addSubview(nameField)
        scope.addItems(withTitles: ["Global", "Local"])
        scope.selectItem(at: preset.scope == .global ? 0 : 1)
        scope.frame = CGRect(x: 110, y: 350, width: 140, height: 28)
        content.addSubview(label("Scope", x: 20, y: 354))
        content.addSubview(scope)
        recorder.hotKey = preset.hotKey
        recorder.frame = CGRect(x: 110, y: 312, width: 170, height: 28)
        content.addSubview(label("Shortcut", x: 20, y: 316))
        content.addSubview(recorder)
        let columns = preset.area.isValid ? preset.area.columns : defaultGrid.columns
        let rows = preset.area.isValid ? preset.area.rows : defaultGrid.rows
        grid.geometry = GridGeometry(columns: columns, rows: rows)
        let area = preset.area
        grid.selection = GridSelection(x: area.x * 2, y: area.y * 2, width: area.width * 2, height: area.height * 2)
        grid.frame = CGRect(x: 20, y: 65, width: 420, height: 228)
        content.addSubview(grid)
        fineCheckbox.frame = CGRect(x: 20, y: 37, width: 130, height: 22)
        fineCheckbox.target = self
        fineCheckbox.action = #selector(toggleFine)
        content.addSubview(fineCheckbox)
        let save = NSButton(title: "Save", target: self, action: #selector(savePreset))
        save.frame = CGRect(x: 350, y: 18, width: 90, height: 30)
        save.keyEquivalent = "\r"
        content.addSubview(save)
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.frame = CGRect(x: 255, y: 18, width: 90, height: 30)
        content.addSubview(cancel)
    }

    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let parent = sender.sheetParent else { return true }
        parent.endSheet(sender, returnCode: .cancel)
        return false
    }

    private func dismiss(_ response: NSApplication.ModalResponse) {
        guard let sheet = window else { return }
        if let parent = sheet.sheetParent { parent.endSheet(sheet, returnCode: response) }
        else { close() }
    }

    private func label(_ text: String, x: CGFloat, y: CGFloat) -> NSTextField {
        let view = NSTextField(labelWithString: text)
        view.frame = CGRect(x: x, y: y, width: 90, height: 20)
        return view
    }

    @objc private func toggleFine() { grid.fineMode = fineCheckbox.state == .on }

    @objc private func savePreset() {
        var updated = preset
        updated.name = nameField.stringValue.isEmpty ? nil : nameField.stringValue
        updated.scope = scope.indexOfSelectedItem == 0 ? .global : .local
        updated.hotKey = recorder.hotKey
        let selection = grid.selection
        if selection.x % 2 == 0 && selection.y % 2 == 0 && selection.width % 2 == 0 && selection.height % 2 == 0 {
            updated.area = StoredGridArea(x: selection.x / 2, y: selection.y / 2, width: selection.width / 2,
                                          height: selection.height / 2, columns: grid.geometry.columns, rows: grid.geometry.rows)
        } else {
            updated.area = StoredGridArea(x: selection.x, y: selection.y, width: selection.width,
                                          height: selection.height, columns: grid.geometry.fineColumns, rows: grid.geometry.fineRows)
        }
        do {
            try onSave(updated)
            dismiss(.OK)
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    @objc private func cancel() { dismiss(.cancel) }
}
