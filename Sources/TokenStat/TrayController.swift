import CGtk
import CAppIndicator

// Manages the system tray icon (AppIndicator) and its dropdown menu.
// render() must be called on GTK's main thread — ClaudeService ensures this
// by dispatching onUpdate through g_idle_add (see GtkHelpers.scheduleGtkUpdate).

final class TrayController {
    private var indicator: OpaquePointer?
    private var menu:      OpaquePointer?

    // Display-only menu items (not clickable)
    private var fiveHourHeaderItem: OpaquePointer?
    private var fiveHourBarItem:    OpaquePointer?
    private var sevenDayHeaderItem: OpaquePointer?
    private var sevenDayBarItem:    OpaquePointer?
    private var sonnetSepItem:      OpaquePointer?
    private var sonnetHeaderItem:   OpaquePointer?
    private var sonnetBarItem:      OpaquePointer?
    private var updatedItem:        OpaquePointer?

    init() {
        buildMenu()

        // "system-run" is available on all Ubuntu/GNOME systems.
        // The percentage label next to it gives the at-a-glance status.
        indicator = app_indicator_new(
            "tokenstat",
            "system-run",
            APP_INDICATOR_CATEGORY_APPLICATION_STATUS
        )
        app_indicator_set_status(indicator, APP_INDICATOR_STATUS_ACTIVE)
        app_indicator_set_label(indicator, "–%", "100%")
        app_indicator_set_menu(indicator, menu)

        ClaudeService.shared.onUpdate = { [unowned self] in self.render() }
        ClaudeService.shared.start()
        render()
    }

    // MARK: - Menu construction

    private func buildMenu() {
        menu = gtk_menu_new()

        fiveHourHeaderItem = display("Current Session")
        fiveHourBarItem    = display("  Updating…")
        separator()

        sevenDayHeaderItem = display("7-Day Window")
        sevenDayBarItem    = display("  Updating…")

        sonnetSepItem    = separator()
        sonnetHeaderItem = display("7-Day Sonnet")
        sonnetBarItem    = display("  Updating…")

        separator()
        updatedItem = display("")
        separator()

        action("Refresh")  { ClaudeService.shared.refresh() }
        action("Settings…") { SettingsWindow.shared.show() }
        separator()
        action("Follow on Instagram") { openURL("https://www.instagram.com/luislacoste_") }
        action("GitHub")              { openURL("https://github.com/luislacoste") }
        separator()
        action("Quit TokenStat") {
            ClaudeService.shared.stop()
            gtk_main_quit()
        }

        gtk_widget_show_all(menu)
    }

    @discardableResult
    private func display(_ label: String) -> OpaquePointer? {
        let item = gtk_menu_item_new_with_label(label)
        gtk_widget_set_sensitive(item, 0)
        gtk_menu_shell_append(menu, item)
        return item
    }

    @discardableResult
    private func separator() -> OpaquePointer? {
        let sep = gtk_separator_menu_item_new()
        gtk_menu_shell_append(menu, sep)
        return sep
    }

    private func action(_ label: String, block: @escaping () -> Void) {
        let item = gtk_menu_item_new_with_label(label)
        connectSignal(item, signal: "activate", block: block)
        gtk_menu_shell_append(menu, item)
    }

    // MARK: - Render

    func render() {
        let svc = ClaudeService.shared

        guard svc.lastError == nil else {
            setLabel(fiveHourHeaderItem, "Current Session")
            setLabel(fiveHourBarItem,    "  \(svc.lastError!)")
            setLabel(sevenDayHeaderItem, "7-Day Window")
            setLabel(sevenDayBarItem,    "")
            showSonnet(false)
            setLabel(updatedItem, "")
            app_indicator_set_label(indicator, "ERR", "ERR")
            return
        }

        let snap    = svc.snapshot
        let fivePct = snap.fiveHourUtilization
        let sevenPct = snap.sevenDayUtilization

        setLabel(fiveHourHeaderItem, "Current Session")
        setLabel(fiveHourBarItem,    barLine(pct: fivePct,  resetIn: snap.fiveHourResetIn))

        setLabel(sevenDayHeaderItem, "7-Day Window")
        setLabel(sevenDayBarItem,    barLine(pct: sevenPct, resetIn: snap.sevenDayResetIn))

        if let sonnetPct = snap.sevenDaySonnetUtilization {
            showSonnet(true)
            setLabel(sonnetHeaderItem, "7-Day Sonnet")
            setLabel(sonnetBarItem,    barLine(pct: sonnetPct, resetIn: nil))
        } else {
            showSonnet(false)
        }

        let fmt = DateFormatter()
        fmt.timeStyle = .short
        fmt.dateStyle = .none
        setLabel(updatedItem, "  Updated \(fmt.string(from: snap.lastUpdated))")

        app_indicator_set_label(indicator, "\(fivePct)%", "100%")
    }

    private func showSonnet(_ visible: Bool) {
        if visible {
            gtk_widget_show(sonnetSepItem)
            gtk_widget_show(sonnetHeaderItem)
            gtk_widget_show(sonnetBarItem)
        } else {
            gtk_widget_hide(sonnetSepItem)
            gtk_widget_hide(sonnetHeaderItem)
            gtk_widget_hide(sonnetBarItem)
        }
    }

    private func setLabel(_ item: OpaquePointer?, _ text: String) {
        gtk_menu_item_set_label(item, text)
    }

    // MARK: - Progress bar text

    private func barLine(pct: Int, resetIn: String?) -> String {
        let width  = 24
        let filled = max(0, min(width, Int((Double(pct) / 100.0 * Double(width)).rounded())))
        let empty  = width - filled
        var s = "  [\(String(repeating: "█", count: filled))\(String(repeating: "░", count: empty))]  \(pct)%"
        if let r = resetIn { s += "  ·  \(r) till reset" }
        return s
    }
}

// MARK: - URL opener

private func openURL(_ urlString: String) {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/xdg-open")
    proc.arguments = [urlString]
    try? proc.run()
}
