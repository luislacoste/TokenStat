import Foundation
import CGtk
import CAppIndicator

// Manages the system tray icon (AppIndicator) and its dropdown menu.
// render() must be called on GTK's main thread — ClaudeService ensures this
// by dispatching onUpdate through g_idle_add (see GtkHelpers.scheduleGtkUpdate).

final class TrayController {
    private var indicator: OpaquePointer?
    private var menu:      OpaquePointer?

    // Display-only menu items (not clickable)
    private var activityLabel:      OpaquePointer?
    private var fiveHourHeaderItem: OpaquePointer?
    private var fiveHourBarItem:    OpaquePointer?
    private var sevenDayHeaderItem: OpaquePointer?
    private var sevenDayBarItem:    OpaquePointer?
    private var sonnetSepItem:      OpaquePointer?
    private var sonnetHeaderItem:   OpaquePointer?
    private var sonnetBarItem:      OpaquePointer?
    private var updatedItem:        OpaquePointer?

    // Two alternating file names so app_indicator_set_icon always points at a
    // path GTK's icon theme cache hasn't already resolved with this content —
    // reusing one fixed name risks a stale cached image on some hosts.
    private let iconDir: String = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/tokenstat/icons").path
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }()
    private var iconToggle = false

    init() {
        buildMenu()

        indicator = appIndicatorNew(
            "tokenstat",
            "tokenstat-icon-a",
            APP_INDICATOR_CATEGORY_APPLICATION_STATUS
        )
        app_indicator_set_icon_theme_path(indicator, iconDir)
        app_indicator_set_status(indicator, APP_INDICATOR_STATUS_ACTIVE)
        app_indicator_set_menu(indicator, menu)

        ClaudeService.shared.onUpdate = { [unowned self] in self.render() }
        ActivityMonitor.shared.onChange = { [unowned self] in self.render() }
        ClaudeService.shared.start()
        ActivityMonitor.shared.start()
        render()
    }

    // MARK: - Menu construction

    private func buildMenu() {
        menu = gtkMenuNew()

        activityLabel = displayMarkup("Claude Code: Ready to prompt")
        separator()

        fiveHourHeaderItem = display("Current Session")
        fiveHourBarItem    = displayMarkup("  Updating…")
        separator()

        sevenDayHeaderItem = display("7-Day Window")
        sevenDayBarItem    = displayMarkup("  Updating…")

        sonnetSepItem    = separator()
        sonnetHeaderItem = display("7-Day Sonnet")
        sonnetBarItem    = displayMarkup("  Updating…")

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
            ActivityMonitor.shared.stop()
            gtk_main_quit()
        }

        gtk_widget_show_all(menu)
    }

    @discardableResult
    private func display(_ label: String) -> OpaquePointer? {
        let item = gtkMenuItemNewWithLabel(label)
        gtk_widget_set_sensitive(item, 0)
        gtk_menu_shell_append(menu, item)
        return item
    }

    /// A display-only item whose child is a plain GtkLabel with Pango markup
    /// enabled, so its text can carry color (e.g. the activity dot). Returns
    /// the label itself — update it with gtk_label_set_markup, not
    /// gtk_menu_item_set_label (that API only understands plain-label items).
    @discardableResult
    private func displayMarkup(_ markup: String) -> OpaquePointer? {
        let item = gtkMenuItemNew()
        gtk_widget_set_sensitive(item, 0)
        let label = gtkLabelNew(nil)
        gtk_label_set_markup(label, markup)
        gtk_label_set_xalign(label, 0)
        gtk_container_add(item, label)
        gtk_menu_shell_append(menu, item)
        return label
    }

    @discardableResult
    private func separator() -> OpaquePointer? {
        let sep = gtkSeparatorMenuItemNew()
        gtk_menu_shell_append(menu, sep)
        return sep
    }

    private func action(_ label: String, block: @escaping () -> Void) {
        let item = gtkMenuItemNewWithLabel(label)
        connectSignal(item, signal: "activate", block: block)
        gtk_menu_shell_append(menu, item)
    }

    // MARK: - Render

    func render() {
        let svc = ClaudeService.shared

        // ── Claude activity (stoplight) ────────────────────
        // AppIndicator exports this menu over DBusMenu (consumed natively by
        // GNOME Shell, not rendered through GTK), which carries plain text
        // only — Pango markup/span colors are silently dropped. Colored
        // square/circle emoji carry their own color from the font glyph
        // itself, so they're the only way to get real color into this menu.
        let activity = ActivityMonitor.shared.state
        let (dot, activityLabelText): (String, String) = {
            switch activity {
            case .blocked: return ("🔴", "Waiting for permission")
            case .working: return ("🟡", "Thinking…")
            case .ready:   return ("🟢", "Ready to prompt")
            }
        }()
        gtk_label_set_text(activityLabel, "\(dot)  Claude Code: \(activityLabelText)")

        guard svc.lastError == nil else {
            setLabel(fiveHourHeaderItem, "Current Session")
            gtk_label_set_text(fiveHourBarItem, "  \(svc.lastError!)")
            setLabel(sevenDayHeaderItem, "7-Day Window")
            gtk_label_set_text(sevenDayBarItem, "")
            showSonnet(false)
            setLabel(updatedItem, "")
            setIcon(fraction: 0, activity: activity)
            return
        }

        let snap    = svc.snapshot
        let fivePct = snap.fiveHourUtilization
        let sevenPct = snap.sevenDayUtilization
        setIcon(fraction: Double(fivePct) / 100.0, activity: activity)

        setLabel(fiveHourHeaderItem, "Current Session")
        gtk_label_set_text(fiveHourBarItem, barLine(pct: fivePct, resetIn: snap.fiveHourResetIn))

        setLabel(sevenDayHeaderItem, "7-Day Window")
        gtk_label_set_text(sevenDayBarItem, barLine(pct: sevenPct, resetIn: snap.sevenDayResetIn))

        if let sonnetPct = snap.sevenDaySonnetUtilization {
            showSonnet(true)
            setLabel(sonnetHeaderItem, "7-Day Sonnet")
            gtk_label_set_text(sonnetBarItem, barLine(pct: sonnetPct, resetIn: nil))
        } else {
            showSonnet(false)
        }

        let fmt = DateFormatter()
        fmt.timeStyle = .short
        fmt.dateStyle = .none
        setLabel(updatedItem, "  Updated \(fmt.string(from: snap.lastUpdated))")
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

    /// Built from colored square emoji rather than Pango markup — DBusMenu
    /// (see the note in render()) carries plain text only.
    private func barLine(pct: Int, resetIn: String?) -> String {
        let width  = 12
        let filled = max(0, min(width, Int((Double(pct) / 100.0 * Double(width)).rounded())))
        let empty  = width - filled

        var s = "  \(String(repeating: colorSquare(for: pct), count: filled))"
        s += "\(String(repeating: "⬜", count: empty))  \(pct)%"
        if let r = resetIn { s += "  ·  \(r) till reset" }
        return s
    }

    private func colorSquare(for pct: Int) -> String {
        switch pct {
        case ..<50: return "🟩"
        case ..<75: return "🟨"
        case ..<90: return "🟧"
        default:    return "🟥"
        }
    }

    // MARK: - Icon (drawn with Cairo — stoplight dots + usage bar, mirroring
    // the macOS build's custom NSImage icon)

    private func setIcon(fraction: Double, activity: ClaudeActivity) {
        let name = drawIcon(fraction: fraction, activity: activity)
        app_indicator_set_icon(indicator, name)
    }

    private func drawIcon(fraction: Double, activity: ClaudeActivity) -> String {
        let lightD: Double = 7, lightGap: Double = 3, pad: Double = 4
        let lightsW = 3 * lightD + 2 * lightGap
        let barW: Double = 46, H: Double = 18, bH: Double = 8, r: Double = 2.5
        let W = lightsW + pad + barW

        let surface = cairo_image_surface_create(CAIRO_FORMAT_ARGB32,
                                                   Int32(W.rounded(.up)),
                                                   Int32(H.rounded(.up)))
        let cr = cairo_create(surface)

        // ── Stoplight: red / yellow / green, active one lit ──
        let lights: [(Double, Double, Double, ClaudeActivity)] = [
            (0.87, 0.19, 0.19, .blocked),
            (0.95, 0.82, 0.10, .working),
            (0.22, 0.62, 0.38, .ready),
        ]
        for (i, (rC, gC, bC, state)) in lights.enumerated() {
            let cx = Double(i) * (lightD + lightGap) + lightD / 2
            let cy = H / 2
            let on = activity == state
            cairo_set_source_rgba(cr, rC, gC, bC, on ? 0.95 : 0.17)
            cairo_arc(cr, cx, cy, lightD / 2, 0, 2 * Double.pi)
            cairo_fill(cr)
        }

        // ── Usage bar ─────────────────────────────────────────
        let bx = lightsW + pad
        let by = (H - bH) / 2
        let bw = barW - 1

        cairo_set_source_rgba(cr, 0.6, 0.6, 0.6, 0.17)
        roundedRect(cr, x: bx, y: by, w: bw, h: bH, r: r)
        cairo_fill(cr)

        if fraction > 0 {
            let fw = max(bH, bw * min(1, fraction))
            let (fr, fg, fb) = barColor(for: fraction)
            cairo_set_source_rgba(cr, fr, fg, fb, 0.95)
            roundedRect(cr, x: bx, y: by, w: fw, h: bH, r: r)
            cairo_fill(cr)
        }

        cairo_set_source_rgba(cr, 0.6, 0.6, 0.6, 0.3)
        cairo_set_line_width(cr, 0.5)
        roundedRect(cr, x: bx, y: by, w: bw, h: bH, r: r)
        cairo_stroke(cr)

        cairo_destroy(cr)

        let name = iconToggle ? "tokenstat-icon-b" : "tokenstat-icon-a"
        iconToggle.toggle()
        cairo_surface_write_to_png(surface, "\(iconDir)/\(name).png")
        cairo_surface_destroy(surface)
        return name
    }

    private func roundedRect(_ cr: OpaquePointer?, x: Double, y: Double, w: Double, h: Double, r: Double) {
        let r = min(r, min(w, h) / 2)
        cairo_new_sub_path(cr)
        cairo_arc(cr, x + w - r, y + r,     r, -Double.pi / 2, 0)
        cairo_arc(cr, x + w - r, y + h - r, r, 0, Double.pi / 2)
        cairo_arc(cr, x + r,     y + h - r, r, Double.pi / 2, Double.pi)
        cairo_arc(cr, x + r,     y + r,     r, Double.pi, 3 * Double.pi / 2)
        cairo_close_path(cr)
    }

    /// Smoothly interpolates green → yellow → red via HSB hue (120° → 0°),
    /// matching the macOS build's coloring.
    private func barColor(for fraction: Double) -> (Double, Double, Double) {
        let t = max(0.0, min(1.0, fraction))
        let hue = (1.0 - t) * (120.0 / 360.0)
        return hsbToRgb(h: hue, s: 0.72, v: 0.88)
    }

    private func hsbToRgb(h: Double, s: Double, v: Double) -> (Double, Double, Double) {
        let i = Int(h * 6) % 6
        let f = h * 6 - Double(Int(h * 6))
        let p = v * (1 - s)
        let q = v * (1 - f * s)
        let t = v * (1 - (1 - f) * s)
        switch i {
        case 0:  return (v, t, p)
        case 1:  return (q, v, p)
        case 2:  return (p, v, t)
        case 3:  return (p, q, v)
        case 4:  return (t, p, v)
        default: return (v, p, q)
        }
    }
}

// MARK: - URL opener

private func openURL(_ urlString: String) {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/xdg-open")
    proc.arguments = [urlString]
    try? proc.run()
}
