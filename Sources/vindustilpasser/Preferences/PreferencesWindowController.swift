import AppKit
import ServiceManagement

@MainActor
final class PreferencesWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate,
                                         NSTableViewDataSource, NSTableViewDelegate {
    private var settings: AppSettings
    private let onChange: (AppSettings) throws -> Void
    private let tabs = NSTabView()
    private let toolbar = NSToolbar(identifier: "SettingsToolbar")
    private let menuBarCheckbox = NSButton(checkboxWithTitle: "Show icon in menu bar", target: nil, action: nil)
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let loginItemStatusLabel = NSTextField(labelWithString: "")
    private let activationRecorder = HotKeyRecorderView()
    private let saveRecorder = HotKeyRecorderView()
    private let restoreRecorder = HotKeyRecorderView()
    private let permissionLabel = NSTextField(labelWithString: "")
    private let columnsField = NSTextField()
    private let rowsField = NSTextField()
    private let gridPreview = GridView()
    private let table = PresetTableView()
    private let savedTable = NSTableView()
    private var presetEditor: PresetEditorController?

    init(settings: AppSettings, onChange: @escaping (AppSettings) throws -> Void) {
        self.settings = settings
        self.onChange = onChange
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 580, height: 400),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Settings"
        window.center()
        super.init(window: window)
        window.delegate = self
        window.toolbarStyle = .preference
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        window.toolbar = toolbar
        tabs.tabViewType = .noTabsNoBorder
        tabs.frame = window.contentView?.bounds ?? .zero
        tabs.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(tabs)
        buildGeneralTab()
        buildGridTab()
        buildShortcutsTab()
        buildSavedWindowsTab()
        toolbar.selectedItemIdentifier = NSToolbarItem.Identifier("General")
        refresh(settings)
    }

    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    override func showWindow(_ sender: Any?) {
        if window?.isVisible != true { refresh(settings) }
        super.showWindow(sender)
    }

    func windowDidBecomeKey(_ notification: Notification) { refreshLoginItemStatus() }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        ["General", "Grid", "Shortcuts", "Saved Windows"].map { NSToolbarItem.Identifier($0) }
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let symbols = ["General": "gearshape", "Grid": "square.grid.3x3", "Shortcuts": "keyboard",
                       "Saved Windows": "macwindow"]
        guard let symbol = symbols[identifier.rawValue] else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = identifier.rawValue
        item.paletteLabel = identifier.rawValue
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: identifier.rawValue)
        item.target = self
        item.action = #selector(selectSection)
        return item
    }

    @objc private func selectSection(_ item: NSToolbarItem) {
        if tabs.selectedTabViewItem?.identifier as? String == "Grid", !saveGridIfNeeded() {
            toolbar.selectedItemIdentifier = NSToolbarItem.Identifier("Grid")
            return
        }
        tabs.selectTabViewItem(withIdentifier: item.itemIdentifier.rawValue)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { saveGridIfNeeded() }

    func refresh(_ settings: AppSettings) {
        self.settings = settings
        menuBarCheckbox.state = settings.general.showMenuBarIcon ? .on : .off
        refreshLoginItemStatus()
        activationRecorder.hotKey = settings.general.activationHotKey
        saveRecorder.hotKey = settings.general.saveWindowHotKey
        restoreRecorder.hotKey = settings.general.restoreWindowHotKey
        columnsField.integerValue = settings.grid.columns
        rowsField.integerValue = settings.grid.rows
        gridPreview.geometry = GridGeometry(columns: settings.grid.columns, rows: settings.grid.rows)
        gridPreview.selection = GridSelection(x: 0, y: 0, width: settings.grid.columns * 2, height: settings.grid.rows * 2)
        permissionLabel.stringValue = AccessibilityPermission.granted ? "Granted" : "Permission required"
        table.reloadData()
        savedTable.reloadData()
    }

    func syncSavedWindows(_ savedWindows: [SavedWindow]) {
        settings.savedWindows = savedWindows
        savedTable.reloadData()
    }

    private func tab(_ title: String) -> NSView {
        let item = NSTabViewItem(identifier: title)
        item.label = title
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 580, height: 400))
        item.view = view
        tabs.addTabViewItem(item)
        return view
    }

    private func label(_ title: String, frame: CGRect) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.frame = frame
        return label
    }

    private func buildGeneralTab() {
        let view = tab("General")
        view.addSubview(label("Activation shortcut", frame: CGRect(x: 30, y: 347, width: 145, height: 22)))
        activationRecorder.frame = CGRect(x: 180, y: 343, width: 160, height: 30)
        activationRecorder.onChange = { [weak self] key in
            guard let self, let key, key.isGlobalValid else {
                self?.showError(SettingsError.invalid)
                self?.activationRecorder.hotKey = self?.settings.general.activationHotKey
                return
            }
            var updated = self.settings
            updated.general.activationHotKey = key
            self.commit(updated)
        }
        view.addSubview(activationRecorder)
        view.addSubview(label("Save window", frame: CGRect(x: 30, y: 307, width: 145, height: 22)))
        saveRecorder.frame = CGRect(x: 180, y: 303, width: 160, height: 30)
        saveRecorder.setAccessibilityLabel("Save window shortcut")
        saveRecorder.onChange = { [weak self] key in
            guard let self, let key, key.isLocalValid else {
                self?.showError(SettingsError.invalid)
                self?.saveRecorder.hotKey = self?.settings.general.saveWindowHotKey
                return
            }
            var updated = self.settings
            updated.general.saveWindowHotKey = key
            self.commit(updated)
        }
        view.addSubview(saveRecorder)
        view.addSubview(label("Restore window", frame: CGRect(x: 30, y: 267, width: 145, height: 22)))
        restoreRecorder.frame = CGRect(x: 180, y: 263, width: 160, height: 30)
        restoreRecorder.setAccessibilityLabel("Restore window shortcut")
        restoreRecorder.onChange = { [weak self] key in
            guard let self, let key, key.isLocalValid else {
                self?.showError(SettingsError.invalid)
                self?.restoreRecorder.hotKey = self?.settings.general.restoreWindowHotKey
                return
            }
            var updated = self.settings
            updated.general.restoreWindowHotKey = key
            self.commit(updated)
        }
        view.addSubview(restoreRecorder)
        menuBarCheckbox.frame = CGRect(x: 30, y: 222, width: 250, height: 25)
        menuBarCheckbox.target = self
        menuBarCheckbox.action = #selector(toggleMenuBar)
        view.addSubview(menuBarCheckbox)
        launchAtLoginCheckbox.frame = CGRect(x: 30, y: 187, width: 250, height: 25)
        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(toggleLaunchAtLogin)
        view.addSubview(launchAtLoginCheckbox)
        loginItemStatusLabel.frame = CGRect(x: 48, y: 164, width: 500, height: 20)
        view.addSubview(loginItemStatusLabel)
        view.addSubview(label("Accessibility:", frame: CGRect(x: 30, y: 128, width: 120, height: 22)))
        permissionLabel.frame = CGRect(x: 150, y: 128, width: 220, height: 22)
        view.addSubview(permissionLabel)
        let request = NSButton(title: "Request Access", target: self, action: #selector(requestAccess))
        request.frame = CGRect(x: 30, y: 82, width: 130, height: 30)
        view.addSubview(request)
        view.addSubview(label("Access is granted in System Settings → Privacy & Security → Accessibility.",
                              frame: CGRect(x: 30, y: 40, width: 520, height: 25)))
    }

    private func buildSavedWindowsTab() {
        let view = tab("Saved Windows")
        let scroll = NSScrollView(frame: CGRect(x: 24, y: 50, width: 532, height: 328))
        scroll.hasVerticalScroller = true
        for (id, title, width) in [("app", "Application", 90.0), ("window", "Window", 145.0),
                                    ("display", "Display", 165.0), ("frame", "Frame", 120.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title
            column.width = width
            savedTable.addTableColumn(column)
        }
        savedTable.headerView = NSTableHeaderView()
        savedTable.dataSource = self
        savedTable.delegate = self
        savedTable.rowHeight = 28
        scroll.documentView = savedTable
        view.addSubview(scroll)
        let remove = NSButton(title: "−", target: self, action: #selector(deleteSavedWindow))
        remove.frame = CGRect(x: 24, y: 17, width: 32, height: 27)
        remove.setAccessibilityLabel("Delete saved window")
        view.addSubview(remove)
    }

    private func buildGridTab() {
        let view = tab("Grid")
        view.addSubview(label("Columns", frame: CGRect(x: 30, y: 337, width: 75, height: 22)))
        columnsField.frame = CGRect(x: 108, y: 334, width: 56, height: 28)
        columnsField.target = self
        columnsField.action = #selector(changeGrid)
        columnsField.setAccessibilityLabel("Grid columns")
        view.addSubview(columnsField)
        view.addSubview(label("Rows", frame: CGRect(x: 204, y: 337, width: 48, height: 22)))
        rowsField.frame = CGRect(x: 258, y: 334, width: 56, height: 28)
        rowsField.target = self
        rowsField.action = #selector(changeGrid)
        rowsField.setAccessibilityLabel("Grid rows")
        view.addSubview(rowsField)
        gridPreview.frame = CGRect(x: 30, y: 83, width: 520, height: 228)
        view.addSubview(gridPreview)
        let description = NSTextField(wrappingLabelWithString:
            "Hold Option in the panel for twice the grid precision.\nShift+arrows resize from the top left.")
        description.frame = CGRect(x: 30, y: 23, width: 520, height: 42)
        view.addSubview(description)
    }

    private func buildShortcutsTab() {
        let view = tab("Shortcuts")
        let scroll = NSScrollView(frame: CGRect(x: 24, y: 50, width: 532, height: 328))
        scroll.hasVerticalScroller = true
        for (id, title, width) in [("area", "Area", 90.0), ("name", "Name", 180.0), ("scope", "Scope", 95.0), ("shortcut", "Shortcut", 145.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            column.title = title
            column.width = width
            table.addTableColumn(column)
        }
        table.headerView = NSTableHeaderView()
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 36
        table.onEdit = { [weak self] in self?.editPreset() }
        table.doubleAction = #selector(editPreset)
        table.target = self
        scroll.documentView = table
        view.addSubview(scroll)
        let addRemove = NSSegmentedControl(frame: CGRect(x: 24, y: 17, width: 64, height: 27))
        addRemove.segmentCount = 2
        addRemove.setLabel("+", forSegment: 0)
        addRemove.setLabel("−", forSegment: 1)
        addRemove.trackingMode = .momentary
        addRemove.target = self
        addRemove.action = #selector(addOrDeletePreset)
        view.addSubview(addRemove)
        let edit = NSButton(title: "Edit", target: self, action: #selector(editPreset))
        edit.frame = CGRect(x: 100, y: 17, width: 70, height: 27)
        view.addSubview(edit)
    }

    @objc private func toggleMenuBar() {
        var updated = settings
        updated.general.showMenuBarIcon = menuBarCheckbox.state == .on
        commit(updated)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if launchAtLoginCheckbox.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            showError(error)
        }
        refreshLoginItemStatus()
    }

    private func refreshLoginItemStatus() {
        let status = SMAppService.mainApp.status
        launchAtLoginCheckbox.state = (status == .enabled || status == .requiresApproval) ? .on : .off
        loginItemStatusLabel.stringValue = status == .requiresApproval
            ? "Allow this app in System Settings → General → Login Items."
            : ""
    }

    @objc private func requestAccess() {
        AccessibilityPermission.request()
        permissionLabel.stringValue = AccessibilityPermission.granted ? "Granted" : "Permission required"
    }

    @objc private func changeGrid() {
        _ = saveGridIfNeeded()
    }

    private func saveGridIfNeeded() -> Bool {
        columnsField.validateEditing()
        rowsField.validateEditing()
        guard let columns = Int(columnsField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)),
              let rows = Int(rowsField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            showError(SettingsError.invalid)
            return false
        }
        guard columns != settings.grid.columns || rows != settings.grid.rows else { return true }
        var updated = settings
        updated.grid.columns = columns
        updated.grid.rows = rows
        do { try accept(updated); return true }
        catch { showError(error); return false }
    }

    @objc private func addOrDeletePreset(_ sender: NSSegmentedControl) {
        if sender.selectedSegment == 0 { addPreset() }
        else if sender.selectedSegment == 1 { deletePreset() }
    }

    @objc private func addPreset() {
        let area = StoredGridArea(x: 0, y: 0, width: settings.grid.columns, height: settings.grid.rows,
                                  columns: settings.grid.columns, rows: settings.grid.rows)
        edit(WindowPreset(id: UUID(), name: nil, scope: .local, hotKey: nil, area: area))
    }

    @objc private func editPreset() {
        guard table.selectedRow >= 0, table.selectedRow < settings.presets.count else { return }
        edit(settings.presets[table.selectedRow])
    }

    private func edit(_ preset: WindowPreset) {
        guard presetEditor == nil, let window else { return }
        let editor = PresetEditorController(preset: preset, defaultGrid: settings.grid) { [weak self] changed in
            guard let self else { return }
            var updated = self.settings
            if let index = updated.presets.firstIndex(where: { $0.id == changed.id }) {
                updated.presets[index] = changed
            } else {
                updated.presets.append(changed)
            }
            try self.accept(updated)
        }
        presetEditor = editor
        if let sheet = editor.window {
            window.beginSheet(sheet) { [weak self] _ in self?.presetEditor = nil }
        }
    }

    @objc private func deletePreset() {
        guard table.selectedRow >= 0, table.selectedRow < settings.presets.count else { return }
        var updated = settings
        updated.presets.remove(at: table.selectedRow)
        commit(updated)
    }

    @objc private func deleteSavedWindow() {
        guard savedTable.selectedRow >= 0, savedTable.selectedRow < settings.savedWindows.count else { return }
        var updated = settings
        updated.savedWindows.remove(at: savedTable.selectedRow)
        commit(updated)
    }

    private func accept(_ updated: AppSettings) throws {
        try onChange(updated)
        refresh(updated)
    }

    private func commit(_ updated: AppSettings) {
        do { try accept(updated) }
        catch { showError(error); refresh(settings) }
    }

    private func showError(_ error: Error) { NSAlert(error: error).runModal() }

    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === savedTable ? settings.savedWindows.count : settings.presets.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView === savedTable {
            let saved = settings.savedWindows[row]
            let value: String
            switch tableColumn?.identifier.rawValue {
            case "app": value = saved.applicationName
            case "window": value = saved.windowName
            case "display": value = "\(saved.displayName) · \(saved.pixelWidth)×\(saved.pixelHeight)"
            default: value = "\(Int(saved.x)), \(Int(saved.y)) · \(Int(saved.width))×\(Int(saved.height))"
            }
            let view = NSTextField(labelWithString: value)
            view.lineBreakMode = .byTruncatingTail
            view.toolTip = value
            return view
        }
        let preset = settings.presets[row]
        if tableColumn?.identifier.rawValue == "area" { return PresetThumbnailView(area: preset.area) }
        let text: String
        switch tableColumn?.identifier.rawValue {
        case "name": text = preset.name ?? "Untitled"
        case "scope": text = preset.scope == .global ? "Global" : "Local"
        default: text = preset.hotKey?.label ?? "—"
        }
        let view = NSTextField(labelWithString: text)
        view.lineBreakMode = .byTruncatingTail
        return view
    }
}
