import AppKit

@MainActor
final class SettingsPanel: NSObject, NSWindowDelegate {
    static let shared = SettingsPanel()
    private override init() {}

    private var window: NSWindow?
    private var intervalField: NSTextField!
    private var notifyCheckbox: NSButton!
    private var botTokenField: NSSecureTextField!
    private var chatIdField: NSTextField!
    private var telegramCheckbox: NSButton!
    private var telegramStatusLabel: NSTextField!
    private var statusLabel:   NSTextField!

    func show() {
        if window == nil { build() }
        intervalField.stringValue    = "\(ClaudeService.shared.refreshInterval)"
        notifyCheckbox.state         = ActivityMonitor.shared.notifyOnReady ? .on : .off
        botTokenField.stringValue    = TelegramNotifier.botToken
        chatIdField.stringValue      = TelegramNotifier.chatID
        telegramCheckbox.state       = TelegramNotifier.enabled ? .on : .off
        telegramStatusLabel.stringValue = ""
        statusLabel.stringValue   = ""
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Build window

    private func build() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "TokenStat Settings"
        w.delegate = self
        w.isReleasedWhenClosed = false
        let v = w.contentView!

        // ── Refresh interval ─────────────────────────────────

        label(v, "Refresh Interval", y: 426, bold: true)
        label(v, "Fetch new data every", y: 398, x: 20, w: 148)

        intervalField = NSTextField(frame: NSRect(x: 172, y: 394, width: 52, height: 24))
        intervalField.alignment      = .center
        intervalField.font           = .monospacedSystemFont(ofSize: 12, weight: .regular)
        intervalField.placeholderString = "5"
        v.addSubview(intervalField)

        label(v, "minutes", y: 398, x: 230, w: 80)
        label(v, "Minimum 1 · Maximum 60", y: 372, small: true)

        // ── Separator ─────────────────────────────────────────

        let box = NSBox(frame: NSRect(x: 0, y: 352, width: 360, height: 1))
        box.boxType = .separator
        v.addSubview(box)

        // ── Notifications ─────────────────────────────────────

        label(v, "Notifications", y: 328, bold: true)

        notifyCheckbox = NSButton(checkboxWithTitle: "Notify when Claude Code turns ready (green)",
                                   target: nil, action: nil)
        notifyCheckbox.frame = NSRect(x: 20, y: 300, width: 320, height: 20)
        v.addSubview(notifyCheckbox)

        // ── Separator ─────────────────────────────────────────

        let box2 = NSBox(frame: NSRect(x: 0, y: 280, width: 360, height: 1))
        box2.boxType = .separator
        v.addSubview(box2)

        // ── Telegram ──────────────────────────────────────────

        label(v, "Telegram", y: 256, bold: true)

        label(v, "Bot Token", y: 228, x: 20, w: 90)
        botTokenField = NSSecureTextField(frame: NSRect(x: 116, y: 224, width: 224, height: 24))
        botTokenField.placeholderString = "123456:ABC-DEF..."
        v.addSubview(botTokenField)

        label(v, "Chat ID", y: 198, x: 20, w: 90)
        chatIdField = NSTextField(frame: NSRect(x: 116, y: 194, width: 224, height: 24))
        chatIdField.placeholderString = "123456789"
        v.addSubview(chatIdField)

        telegramCheckbox = NSButton(checkboxWithTitle: "Notify via Telegram when ready",
                                     target: nil, action: nil)
        telegramCheckbox.frame = NSRect(x: 20, y: 168, width: 320, height: 20)
        v.addSubview(telegramCheckbox)

        let testBtn = NSButton(title: "Test", target: self, action: #selector(onTestTelegram))
        testBtn.frame      = NSRect(x: 20, y: 136, width: 90, height: 24)
        testBtn.bezelStyle = .rounded
        v.addSubview(testBtn)

        telegramStatusLabel = NSTextField(labelWithString: "")
        telegramStatusLabel.frame     = NSRect(x: 118, y: 140, width: 222, height: 18)
        telegramStatusLabel.font      = .systemFont(ofSize: 11)
        telegramStatusLabel.textColor = .secondaryLabelColor
        v.addSubview(telegramStatusLabel)

        // ── Separator ─────────────────────────────────────────

        let box3 = NSBox(frame: NSRect(x: 0, y: 118, width: 360, height: 1))
        box3.boxType = .separator
        v.addSubview(box3)

        // ── Follow ────────────────────────────────────────────

        label(v, "Follow", y: 94, bold: true)

        let igBtn = linkButton("Instagram", action: #selector(openInstagram),
                               frame: NSRect(x: 20, y: 64, width: 140, height: 26))
        v.addSubview(igBtn)

        let ghBtn = linkButton("GitHub", action: #selector(openGitHub),
                               frame: NSRect(x: 168, y: 64, width: 100, height: 26))
        v.addSubview(ghBtn)

        // ── Status / buttons ──────────────────────────────────

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.frame     = NSRect(x: 20, y: 34, width: 240, height: 18)
        statusLabel.font      = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        v.addSubview(statusLabel)

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(onCancel))
        cancel.frame       = NSRect(x: 216, y: 14, width: 72, height: 26)
        cancel.bezelStyle  = .rounded
        cancel.keyEquivalent = "\u{1b}"
        v.addSubview(cancel)

        let save = NSButton(title: "Save", target: self, action: #selector(onSave))
        save.frame       = NSRect(x: 296, y: 14, width: 52, height: 26)
        save.bezelStyle  = .rounded
        save.keyEquivalent = "\r"
        v.addSubview(save)

        self.window = w
    }

    // MARK: - Actions

    @objc private func onSave() {
        let raw = intervalField.stringValue.trimmingCharacters(in: .whitespaces)
        guard let v = Int(raw), (1...60).contains(v) else {
            statusLabel.stringValue = "Enter a number between 1 and 60."
            statusLabel.textColor   = .systemOrange
            return
        }
        let botTok = botTokenField.stringValue.trimmingCharacters(in: .whitespaces)
        let chatId = chatIdField.stringValue.trimmingCharacters(in: .whitespaces)
        if telegramCheckbox.state == .on, botTok.isEmpty || chatId.isEmpty {
            statusLabel.stringValue = "Enter a Bot Token and Chat ID to enable Telegram."
            statusLabel.textColor   = .systemOrange
            return
        }

        ClaudeService.shared.refreshInterval = v
        ClaudeService.shared.refresh()
        ActivityMonitor.shared.notifyOnReady = (notifyCheckbox.state == .on)
        TelegramNotifier.botToken = botTok
        TelegramNotifier.chatID   = chatId
        TelegramNotifier.enabled  = (telegramCheckbox.state == .on)
        statusLabel.stringValue = "Saved"
        statusLabel.textColor   = .systemGreen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.window?.close() }
    }

    @objc private func onCancel() { window?.close() }

    @objc private func onTestTelegram() {
        let tok = botTokenField.stringValue.trimmingCharacters(in: .whitespaces)
        let cid = chatIdField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !tok.isEmpty, !cid.isEmpty else {
            telegramStatusLabel.stringValue = "Enter a Bot Token and Chat ID first."
            telegramStatusLabel.textColor   = .systemOrange
            return
        }
        telegramStatusLabel.stringValue = "Sending…"
        telegramStatusLabel.textColor   = .secondaryLabelColor
        TelegramNotifier.send(text: "✅ TokenStat test message", botToken: tok, chatID: cid) { error in
            if let error {
                self.telegramStatusLabel.stringValue = error
                self.telegramStatusLabel.textColor   = .systemRed
            } else {
                self.telegramStatusLabel.stringValue = "Sent! Check Telegram."
                self.telegramStatusLabel.textColor   = .systemGreen
            }
        }
    }

    @objc private func openInstagram() {
        NSWorkspace.shared.open(URL(string: "https://www.instagram.com/luislacoste_")!)
    }

    @objc private func openGitHub() {
        NSWorkspace.shared.open(URL(string: "https://github.com/luislacoste")!)
    }

    // MARK: - Layout helpers

    @discardableResult
    private func label(_ v: NSView, _ text: String, y: CGFloat,
                       x: CGFloat = 20, w: CGFloat = 320,
                       bold: Bool = false, small: Bool = false) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.frame = NSRect(x: x, y: y, width: w, height: 20)
        if bold  { f.font      = .boldSystemFont(ofSize: 12) }
        if small { f.font      = .systemFont(ofSize: 11)
                   f.textColor = .secondaryLabelColor }
        v.addSubview(f)
        return f
    }

    private func linkButton(_ title: String, action: Selector, frame: NSRect) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.frame      = frame
        b.bezelStyle = .rounded
        return b
    }
}
