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
    private let permissionLabel = NSTextField(labelWithString: "")
    private let columnsField = NSTextField()
    private let rowsField = NSTextField()
    private let gridPreview = GridView()
    private let table = PresetTableView()
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
        ["General", "Grid", "Shortcuts"].map { NSToolbarItem.Identifier($0) }
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let symbols = ["General": "gearshape", "Grid": "square.grid.3x3", "Shortcuts": "keyboard"]
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
        columnsField.integerValue = settings.grid.columns
        rowsField.integerValue = settings.grid.rows
        gridPreview.geometry = GridGeometry(columns: settings.grid.columns, rows: settings.grid.rows)
        gridPreview.selection = GridSelection(x: 0, y: 0, width: settings.grid.columns * 2, height: settings.grid.rows * 2)
        permissionLabel.stringValue = AccessibilityPermission.granted ? "Granted" : "Permission required"
        table.reloadData()
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
        view.addSubview(label("Activation shortcut", frame: CGRect(x: 30, y: 322, width: 145, height: 22)))
        activationRecorder.frame = CGRect(x: 180, y: 318, width: 160, height: 30)
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
        menuBarCheckbox.frame = CGRect(x: 30, y: 267, width: 250, height: 25)
        menuBarCheckbox.target = self
        menuBarCheckbox.action = #selector(toggleMenuBar)
        view.addSubview(menuBarCheckbox)
        launchAtLoginCheckbox.frame = CGRect(x: 30, y: 231, width: 250, height: 25)
        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(toggleLaunchAtLogin)
        view.addSubview(launchAtLoginCheckbox)
        loginItemStatusLabel.frame = CGRect(x: 48, y: 207, width: 500, height: 20)
        view.addSubview(loginItemStatusLabel)
        view.addSubview(label("Accessibility:", frame: CGRect(x: 30, y: 169, width: 120, height: 22)))
        permissionLabel.frame = CGRect(x: 150, y: 169, width: 220, height: 22)
        view.addSubview(permissionLabel)
        let request = NSButton(title: "Request Access", target: self, action: #selector(requestAccess))
        request.frame = CGRect(x: 30, y: 124, width: 130, height: 30)
        view.addSubview(request)
        view.addSubview(label("Access is granted in System Settings → Privacy & Security → Accessibility.",
                              frame: CGRect(x: 30, y: 83, width: 520, height: 25)))
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

    private func accept(_ updated: AppSettings) throws {
        try onChange(updated)
        refresh(updated)
    }

    private func commit(_ updated: AppSettings) {
        do { try accept(updated) }
        catch { showError(error); refresh(settings) }
    }

    private func showError(_ error: Error) { NSAlert(error: error).runModal() }

    func numberOfRows(in tableView: NSTableView) -> Int { settings.presets.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
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
