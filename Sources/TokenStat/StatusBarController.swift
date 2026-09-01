import AppKit

@MainActor
final class StatusBarController {
    private let item: NSStatusItem
    private let menu = NSMenu()

    // 5-Hour
    private let fiveHourHeader = NSMenuItem()
    private let fiveHourLine   = NSMenuItem()
    // 7-Day
    private let sevenDayHeader = NSMenuItem()
    private let sevenDayLine   = NSMenuItem()
    // 7-Day Sonnet
    private let sonnetSep    = NSMenuItem.separator()
    private let sonnetHeader = NSMenuItem()
    private let sonnetLine   = NSMenuItem()
    // Claude activity
    private let activityItem = NSMenuItem()
    // Meta
    private let updatedItem  = NSMenuItem()

    init() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        buildMenu()
        item.menu = menu
        ClaudeService.shared.onUpdate = { [weak self] in self?.render() }
        ActivityMonitor.shared.onChange = { [weak self] in self?.render() }
        ClaudeService.shared.start()
        ActivityMonitor.shared.start()
        render()
    }

    // MARK: - Menu structure

    private func buildMenu() {
        func display(_ mi: NSMenuItem) { mi.isEnabled = false; menu.addItem(mi) }

        display(activityItem)
        menu.addItem(.separator())

        display(fiveHourHeader)
        display(fiveHourLine)
        menu.addItem(.separator())

        display(sevenDayHeader)
        display(sevenDayLine)

        menu.addItem(sonnetSep)
        display(sonnetHeader)
        display(sonnetLine)

        menu.addItem(.separator())
        display(updatedItem)
        menu.addItem(.separator())

        add("Refresh",          key: "r", action: #selector(onRefresh))
        add("Settings…",        key: ",", action: #selector(onSettings))
        menu.addItem(.separator())
        add("Follow on Instagram", key: "", action: #selector(openInstagram))
        add("GitHub",              key: "", action: #selector(openGitHub))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit TokenStat",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
    }

    private func add(_ title: String, key: String, action: Selector) {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
        mi.target = self
        menu.addItem(mi)
    }

    // MARK: - Render

    private func render() {
        let svc = ClaudeService.shared

        // ── Claude activity (stoplight) ────────────────────
        let activity = ActivityMonitor.shared.state
        let (dot, label): (NSColor, String) = {
            switch activity {
            case .blocked: return (.systemRed,    "Waiting for permission")
            case .working: return (.systemYellow, "Thinking…")
            case .ready:   return (.systemGreen,  "Ready to prompt")
            }
        }()
        let actLine = NSMutableAttributedString()
        actLine.append(NSAttributedString(string: "● ", attributes: [
            .foregroundColor: dot,
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold)
        ]))
        actLine.append(NSAttributedString(string: "Claude Code: \(label)", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold)
        ]))
        activityItem.attributedTitle = actLine

        guard svc.lastError == nil else {
            setIcon(fraction: 0, color: .secondaryLabelColor)
            fiveHourHeader.attributedTitle = sectionHeader("Current Session")
            fiveHourLine.attributedTitle   = plain("  \(svc.lastError!)")
            sevenDayHeader.attributedTitle = sectionHeader("7-Day Window")
            sevenDayLine.title = ""
            showSonnet(false)
            updatedItem.title = ""
            return
        }

        let snap = svc.snapshot

        // ── Icon (5-hour utilization) ──────────────────────
        let fiveFrac = Double(snap.fiveHourUtilization) / 100.0
        setIcon(fraction: fiveFrac, color: color(for: snap.fiveHourUtilization))

        // ── Current Session ────────────────────────────────
        fiveHourHeader.attributedTitle = sectionHeader("Current Session")
        fiveHourLine.attributedTitle   = usageLine(frac: fiveFrac,
                                                   pct: snap.fiveHourUtilization,
                                                   resetIn: snap.fiveHourResetIn)

        // ── 7-Day ──────────────────────────────────────────
        let sevenFrac = Double(snap.sevenDayUtilization) / 100.0
        sevenDayHeader.attributedTitle = sectionHeader("7-Day Window")
        sevenDayLine.attributedTitle   = usageLine(frac: sevenFrac,
                                                   pct: snap.sevenDayUtilization,
                                                   resetIn: snap.sevenDayResetIn)

        // ── 7-Day Sonnet ───────────────────────────────────
        if let sonnetPct = snap.sevenDaySonnetUtilization {
            showSonnet(true)
            let sonnetFrac = Double(sonnetPct) / 100.0
            sonnetHeader.attributedTitle = sectionHeader("7-Day Sonnet")
            sonnetLine.attributedTitle   = usageLine(frac: sonnetFrac, pct: sonnetPct, resetIn: nil)
        } else {
            showSonnet(false)
        }

        // ── Updated ────────────────────────────────────────
        let tf = DateFormatter(); tf.timeStyle = .short; tf.dateStyle = .none
        updatedItem.attributedTitle = plain("  Updated \(tf.string(from: snap.lastUpdated))",
                                            color: .secondaryLabelColor)
    }

    private func showSonnet(_ visible: Bool) {
        sonnetSep.isHidden    = !visible
        sonnetHeader.isHidden = !visible
        sonnetLine.isHidden   = !visible
    }

    // MARK: - Attributed string builders

    /// Colored bar + percentage + optional reset countdown on one line.
    private func usageLine(frac: Double, pct: Int, resetIn: String?) -> NSAttributedString {
        let barColor = color(for: pct)
        let out      = NSMutableAttributedString()
        let width    = 24
        let filled   = max(0, min(width, Int((frac * Double(width)).rounded())))

        out += mono("  [")
        if filled > 0 {
            out += mono(String(repeating: "█", count: filled), fg: barColor)
        }
        if width - filled > 0 {
            out += mono(String(repeating: "░", count: width - filled),
                        fg: .secondaryLabelColor.withAlphaComponent(0.4))
        }
        out += mono("]  ")
        out += mono("\(pct)%", fg: barColor, weight: .medium)
        if let r = resetIn {
            out += mono("  ·  \(r) till reset", fg: .secondaryLabelColor)
        }
        return out
    }

    private func sectionHeader(_ title: String) -> NSAttributedString {
        NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold)
        ])
    }

    private func plain(_ s: String, color: NSColor? = nil) -> NSAttributedString {
        mono(s, fg: color)
    }

    private func mono(_ s: String,
                      fg: NSColor? = nil,
                      weight: NSFont.Weight = .regular) -> NSAttributedString {
        var attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: weight)
        ]
        if let c = fg { attrs[.foregroundColor] = c }
        return NSAttributedString(string: s, attributes: attrs)
    }

    // MARK: - Color

    /// Smoothly interpolates green → yellow → red via HSB hue (120° → 0°).
    private func color(for pct: Int) -> NSColor {
        let t   = max(0.0, min(1.0, Double(pct) / 100.0))
        let hue = (1.0 - t) * (120.0 / 360.0)   // 0.333 (green) → 0.0 (red)
        return NSColor(hue: hue, saturation: 0.80, brightness: 0.90, alpha: 1.0)
    }

    // MARK: - Icon

    private func setIcon(fraction: Double, color: NSColor) {
        item.button?.image = drawIcon(fraction: fraction, fill: color,
                                      activity: ActivityMonitor.shared.state)
        item.button?.title = ""
        item.button?.imageScaling = .scaleProportionallyDown
    }

    private func drawIcon(fraction: Double, fill: NSColor,
                          activity: ClaudeActivity) -> NSImage {
        let lightD: CGFloat = 6.5, lightGap: CGFloat = 3, pad: CGFloat = 6
        let lightsW = 3 * lightD + 2 * lightGap
        let barW: CGFloat = 46, H: CGFloat = 18, bH: CGFloat = 8, r: CGFloat = 2.5
        let W = lightsW + pad + barW

        let img = NSImage(size: NSSize(width: W, height: H))
        img.lockFocus()
        defer { img.unlockFocus() }

        // ── Stoplight: red / yellow / green, active one lit ──
        let lights: [(NSColor, ClaudeActivity)] = [
            (.systemRed,    .blocked),
            (.systemYellow, .working),
            (.systemGreen,  .ready),
        ]
        for (i, (c, st)) in lights.enumerated() {
            let x  = CGFloat(i) * (lightD + lightGap)
            let on = activity == st
            let dot = NSRect(x: x, y: (H - lightD) / 2, width: lightD, height: lightD)
            c.withAlphaComponent(on ? 1.0 : 0.18).setFill()
            NSBezierPath(ovalIn: dot).fill()
            if on {
                c.withAlphaComponent(0.35).setStroke()
                let halo = NSBezierPath(ovalIn: dot.insetBy(dx: -1.5, dy: -1.5))
                halo.lineWidth = 1; halo.stroke()
            }
        }

        // ── Usage bar ─────────────────────────────────────────
        let bx = lightsW + pad
        let rect = NSRect(x: bx, y: (H - bH) / 2, width: barW - 2, height: bH)
        NSColor.secondaryLabelColor.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()

        if fraction > 0 {
            let fw = max(bH, (barW - 2) * CGFloat(fraction))
            fill.setFill()
            NSBezierPath(roundedRect: NSRect(x: bx, y: rect.minY, width: fw, height: bH),
                         xRadius: r, yRadius: r).fill()
        }

        NSColor.secondaryLabelColor.withAlphaComponent(0.35).setStroke()
        let border = NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r)
        border.lineWidth = 0.5; border.stroke()
        return img
    }

    // MARK: - Actions

    @objc private func onRefresh()     { ClaudeService.shared.refresh() }
    @objc private func onSettings()    { SettingsPanel.shared.show() }
    @objc private func openInstagram() { NSWorkspace.shared.open(URL(string: "https://www.instagram.com/luislacoste_")!) }
    @objc private func openGitHub()    { NSWorkspace.shared.open(URL(string: "https://github.com/luislacoste")!) }
}

// MARK: - NSMutableAttributedString += helper

private func += (lhs: NSMutableAttributedString, rhs: NSAttributedString) {
    lhs.append(rhs)
}
