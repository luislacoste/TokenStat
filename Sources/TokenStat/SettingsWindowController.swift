import AppKit

@MainActor
final class SettingsPanel: NSObject, NSWindowDelegate {
    static let shared = SettingsPanel()
    private override init() {}

    private var window: NSWindow?
    private var intervalField: NSTextField!
    private var statusLabel:   NSTextField!

    func show() {
        if window == nil { build() }
        intervalField.stringValue = "\(ClaudeService.shared.refreshInterval)"
        statusLabel.stringValue   = ""
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Build window

    private func build() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "TokenStat Settings"
        w.delegate = self
        w.isReleasedWhenClosed = false
        let v = w.contentView!

        // ── Refresh interval ─────────────────────────────────

        label(v, "Refresh Interval", y: 206, bold: true)
        label(v, "Fetch new data every", y: 178, x: 20, w: 148)

        intervalField = NSTextField(frame: NSRect(x: 172, y: 174, width: 52, height: 24))
        intervalField.alignment      = .center
        intervalField.font           = .monospacedSystemFont(ofSize: 12, weight: .regular)
        intervalField.placeholderString = "5"
        v.addSubview(intervalField)

        label(v, "minutes", y: 178, x: 230, w: 80)
        label(v, "Minimum 1 · Maximum 60", y: 152, small: true)

        // ── Separator ─────────────────────────────────────────

        let box = NSBox(frame: NSRect(x: 0, y: 132, width: 360, height: 1))
        box.boxType = .separator
        v.addSubview(box)

        // ── Follow ────────────────────────────────────────────

        label(v, "Follow", y: 108, bold: true)

        let igBtn = linkButton("Instagram", action: #selector(openInstagram),
                               frame: NSRect(x: 20, y: 78, width: 140, height: 26))
        v.addSubview(igBtn)

        let ghBtn = linkButton("GitHub", action: #selector(openGitHub),
                               frame: NSRect(x: 168, y: 78, width: 100, height: 26))
        v.addSubview(ghBtn)

        // ── Status / buttons ──────────────────────────────────

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.frame     = NSRect(x: 20, y: 48, width: 240, height: 18)
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
        ClaudeService.shared.refreshInterval = v
        ClaudeService.shared.refresh()
        statusLabel.stringValue = "Saved"
        statusLabel.textColor   = .systemGreen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.window?.close() }
    }

    @objc private func onCancel() { window?.close() }

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
