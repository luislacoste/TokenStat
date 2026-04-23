import CGtk

// Settings dialog — refresh interval picker.
// GTK3 equivalent of the macOS NSWindow-based SettingsPanel.

final class SettingsWindow {
    static let shared = SettingsWindow()
    private init() {}

    private var window:        OpaquePointer?
    private var intervalEntry: OpaquePointer?
    private var statusLabel:   OpaquePointer?

    func show() {
        if window == nil { build() }
        let text = "\(ClaudeService.shared.refreshInterval)"
        gtk_entry_set_text(intervalEntry, text)
        gtk_label_set_text(statusLabel, "")
        gtk_widget_show_all(window)
        gtk_window_present(window)
    }

    // MARK: - Build

    private func build() {
        let win = gtk_window_new(GTK_WINDOW_TOPLEVEL)
        gtk_window_set_title(win, "TokenStat Settings")
        gtk_window_set_default_size(win, 380, 160)
        gtk_window_set_resizable(win, 0)
        gtk_container_set_border_width(win, 20)

        // Prevent destroy — just hide so it can be re-shown.
        let winRef = win   // captured by closure; OpaquePointer is a value type
        connectDeleteEvent(win) { gtk_widget_hide(winRef) }

        // Root vertical box
        let vbox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 12)
        gtk_container_add(win, vbox)

        // Row: "Fetch new data every [__] minutes (1–60)"
        let hbox = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8)
        gtk_box_pack_start(vbox, hbox, 0, 0, 0)

        let prefixLabel = gtk_label_new("Fetch new data every")
        gtk_box_pack_start(hbox, prefixLabel, 0, 0, 0)

        intervalEntry = gtk_entry_new()
        gtk_entry_set_width_chars(intervalEntry, 5)
        gtk_entry_set_alignment(intervalEntry, 0.5)
        gtk_box_pack_start(hbox, intervalEntry, 0, 0, 0)

        let suffixLabel = gtk_label_new("minutes  (1–60)")
        gtk_box_pack_start(hbox, suffixLabel, 0, 0, 0)

        // Status label
        statusLabel = gtk_label_new("")
        gtk_box_pack_start(vbox, statusLabel, 0, 0, 0)

        // Spacer
        let spacer = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)
        gtk_box_pack_start(vbox, spacer, 1, 1, 0)

        // Button row
        let btnBox = gtk_button_box_new(GTK_ORIENTATION_HORIZONTAL)
        gtk_button_box_set_layout(btnBox, GTK_BUTTONBOX_END)
        gtk_box_set_spacing(btnBox, 8)
        gtk_box_pack_start(vbox, btnBox, 0, 0, 0)

        let cancelBtn = gtk_button_new_with_label("Cancel")
        connectSignal(cancelBtn, signal: "clicked") { gtk_widget_hide(winRef) }
        gtk_container_add(btnBox, cancelBtn)

        let saveBtn = gtk_button_new_with_label("Save")
        connectSignal(saveBtn, signal: "clicked") { [weak self] in self?.onSave() }
        gtk_container_add(btnBox, saveBtn)

        self.window = win
    }

    // MARK: - Actions

    private func onSave() {
        guard
            let entry = intervalEntry,
            let cStr  = gtk_entry_get_text(entry),
            let v     = Int(String(cString: cStr)),
            (1...60).contains(v)
        else {
            gtk_label_set_text(statusLabel, "Enter a number between 1 and 60.")
            return
        }
        ClaudeService.shared.refreshInterval = v
        ClaudeService.shared.refresh()
        gtk_label_set_text(statusLabel, "Saved!")

        let win = window
        let sl  = statusLabel
        Task.detached {
            try? await Task.sleep(nanoseconds: 600_000_000)
            scheduleGtkUpdate {
                gtk_label_set_text(sl, "")
                gtk_widget_hide(win)
            }
        }
    }
}
