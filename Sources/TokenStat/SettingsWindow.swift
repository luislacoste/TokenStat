import Foundation
import CGtk

// Settings dialog — refresh interval, ready notifications, Telegram.
// GTK3 equivalent of the macOS NSWindow-based SettingsPanel.

final class SettingsWindow {
    static let shared = SettingsWindow()
    private init() {}

    private var window:            OpaquePointer?
    private var intervalEntry:     OpaquePointer?
    private var notifyCheckbox:    OpaquePointer?
    private var botTokenEntry:     OpaquePointer?
    private var chatIdEntry:       OpaquePointer?
    private var telegramCheckbox:  OpaquePointer?
    private var telegramStatusLabel: OpaquePointer?
    private var statusLabel:       OpaquePointer?

    func show() {
        if window == nil { build() }
        gtk_entry_set_text(intervalEntry, "\(ClaudeService.shared.refreshInterval)")
        gtk_toggle_button_set_active(notifyCheckbox, ActivityMonitor.shared.notifyOnReady ? 1 : 0)
        gtk_entry_set_text(botTokenEntry, TelegramNotifier.botToken)
        gtk_entry_set_text(chatIdEntry,   TelegramNotifier.chatID)
        gtk_toggle_button_set_active(telegramCheckbox, TelegramNotifier.enabled ? 1 : 0)
        gtk_label_set_text(telegramStatusLabel, "")
        gtk_label_set_text(statusLabel, "")
        gtk_widget_show_all(window)
        gtk_window_present(window)
    }

    // MARK: - Build

    private func build() {
        let win = gtkWindowNew(GTK_WINDOW_TOPLEVEL)
        gtk_window_set_title(win, "TokenStat Settings")
        gtk_window_set_default_size(win, 420, 480)
        gtk_window_set_resizable(win, 0)
        gtk_container_set_border_width(win, 20)

        // Prevent destroy — just hide so it can be re-shown.
        let winRef = win   // captured by closure; OpaquePointer is a value type
        connectDeleteEvent(win) { gtk_widget_hide(winRef) }

        // Root vertical box
        let vbox = gtkBoxNew(GTK_ORIENTATION_VERTICAL, 12)
        gtk_container_add(win, vbox)

        // ── Refresh interval ─────────────────────────────────

        gtk_box_pack_start(vbox, boldLabel("Refresh Interval"), 0, 0, 0)

        let hbox = gtkBoxNew(GTK_ORIENTATION_HORIZONTAL, 8)
        gtk_box_pack_start(vbox, hbox, 0, 0, 0)

        let prefixLabel = gtkLabelNew("Fetch new data every")
        gtk_box_pack_start(hbox, prefixLabel, 0, 0, 0)

        intervalEntry = gtkEntryNew()
        gtk_entry_set_width_chars(intervalEntry, 5)
        gtk_entry_set_alignment(intervalEntry, 0.5)
        gtk_box_pack_start(hbox, intervalEntry, 0, 0, 0)

        let suffixLabel = gtkLabelNew("minutes  (1–60)")
        gtk_box_pack_start(hbox, suffixLabel, 0, 0, 0)

        gtk_box_pack_start(vbox, separator(), 0, 0, 4)

        // ── Notifications ─────────────────────────────────────

        gtk_box_pack_start(vbox, boldLabel("Notifications"), 0, 0, 0)

        notifyCheckbox = gtkCheckButtonNewWithLabel("Notify when Claude Code turns ready (green)")
        gtk_box_pack_start(vbox, notifyCheckbox, 0, 0, 0)

        gtk_box_pack_start(vbox, separator(), 0, 0, 4)

        // ── Telegram ──────────────────────────────────────────

        gtk_box_pack_start(vbox, boldLabel("Telegram"), 0, 0, 0)

        let tokenRow = gtkBoxNew(GTK_ORIENTATION_HORIZONTAL, 8)
        gtk_box_pack_start(vbox, tokenRow, 0, 0, 0)
        let tokenLabel = gtkLabelNew("Bot Token")
        gtk_label_set_width_chars(tokenLabel, 10)
        gtk_label_set_xalign(tokenLabel, 0)
        gtk_box_pack_start(tokenRow, tokenLabel, 0, 0, 0)
        botTokenEntry = gtkEntryNew()
        gtk_entry_set_visibility(botTokenEntry, 0)
        gtk_entry_set_placeholder_text(botTokenEntry, "123456:ABC-DEF...")
        gtk_box_pack_start(tokenRow, botTokenEntry, 1, 1, 0)

        let chatRow = gtkBoxNew(GTK_ORIENTATION_HORIZONTAL, 8)
        gtk_box_pack_start(vbox, chatRow, 0, 0, 0)
        let chatLabel = gtkLabelNew("Chat ID")
        gtk_label_set_width_chars(chatLabel, 10)
        gtk_label_set_xalign(chatLabel, 0)
        gtk_box_pack_start(chatRow, chatLabel, 0, 0, 0)
        chatIdEntry = gtkEntryNew()
        gtk_entry_set_placeholder_text(chatIdEntry, "123456789")
        gtk_box_pack_start(chatRow, chatIdEntry, 1, 1, 0)

        telegramCheckbox = gtkCheckButtonNewWithLabel("Notify via Telegram when ready")
        gtk_box_pack_start(vbox, telegramCheckbox, 0, 0, 0)

        let testRow = gtkBoxNew(GTK_ORIENTATION_HORIZONTAL, 8)
        gtk_box_pack_start(vbox, testRow, 0, 0, 0)
        let testBtn = gtkButtonNewWithLabel("Test")
        connectSignal(testBtn, signal: "clicked") { [weak self] in self?.onTestTelegram() }
        gtk_box_pack_start(testRow, testBtn, 0, 0, 0)
        telegramStatusLabel = gtkLabelNew("")
        gtk_label_set_xalign(telegramStatusLabel, 0)
        gtk_box_pack_start(testRow, telegramStatusLabel, 1, 1, 0)

        gtk_box_pack_start(vbox, separator(), 0, 0, 4)

        // Status label
        statusLabel = gtkLabelNew("")
        gtk_label_set_xalign(statusLabel, 0)
        gtk_box_pack_start(vbox, statusLabel, 0, 0, 0)

        // Spacer
        let spacer = gtkBoxNew(GTK_ORIENTATION_VERTICAL, 0)
        gtk_box_pack_start(vbox, spacer, 1, 1, 0)

        // Button row
        let btnBox = gtkButtonBoxNew(GTK_ORIENTATION_HORIZONTAL)
        gtk_button_box_set_layout(btnBox, GTK_BUTTONBOX_END)
        gtk_box_set_spacing(btnBox, 8)
        gtk_box_pack_start(vbox, btnBox, 0, 0, 0)

        let cancelBtn = gtkButtonNewWithLabel("Cancel")
        connectSignal(cancelBtn, signal: "clicked") { gtk_widget_hide(winRef) }
        gtk_container_add(btnBox, cancelBtn)

        let saveBtn = gtkButtonNewWithLabel("Save")
        connectSignal(saveBtn, signal: "clicked") { [weak self] in self?.onSave() }
        gtk_container_add(btnBox, saveBtn)

        self.window = win
    }

    private func boldLabel(_ text: String) -> OpaquePointer? {
        let label = gtkLabelNew(nil)
        gtk_label_set_markup(label, "<b>\(text)</b>")
        gtk_label_set_xalign(label, 0)
        return label
    }

    private func separator() -> OpaquePointer? {
        gtkSeparatorNew(GTK_ORIENTATION_HORIZONTAL)
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

        let botTok = entryText(botTokenEntry)
        let chatId = entryText(chatIdEntry)
        let telegramOn = gtk_toggle_button_get_active(telegramCheckbox) != 0
        if telegramOn, botTok.isEmpty || chatId.isEmpty {
            gtk_label_set_text(statusLabel, "Enter a Bot Token and Chat ID to enable Telegram.")
            return
        }

        ClaudeService.shared.refreshInterval = v
        ClaudeService.shared.refresh()
        ActivityMonitor.shared.notifyOnReady = gtk_toggle_button_get_active(notifyCheckbox) != 0
        TelegramNotifier.botToken = botTok
        TelegramNotifier.chatID   = chatId
        TelegramNotifier.enabled  = telegramOn
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

    private func onTestTelegram() {
        let tok = entryText(botTokenEntry)
        let cid = entryText(chatIdEntry)
        guard !tok.isEmpty, !cid.isEmpty else {
            gtk_label_set_text(telegramStatusLabel, "Enter a Bot Token and Chat ID first.")
            return
        }
        gtk_label_set_text(telegramStatusLabel, "Sending…")
        let sl = telegramStatusLabel
        TelegramNotifier.send(text: "✅ TokenStat test message", botToken: tok, chatID: cid) { error in
            scheduleGtkUpdate {
                if let error {
                    gtk_label_set_text(sl, error)
                } else {
                    gtk_label_set_text(sl, "Sent! Check Telegram.")
                }
            }
        }
    }

    private func entryText(_ entry: OpaquePointer?) -> String {
        guard let entry, let cStr = gtk_entry_get_text(entry) else { return "" }
        return String(cString: cStr).trimmingCharacters(in: .whitespaces)
    }
}
