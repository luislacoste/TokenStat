import CGtk
import CAppIndicator

// MARK: - ClosureBox
// Heap-allocates a Swift closure so it can be passed through C as a raw pointer.

final class ClosureBox {
    let closure: () -> Void
    init(_ closure: @escaping () -> Void) { self.closure = closure }
}

// MARK: - Non-capturing @convention(c) callbacks

// Used by g_idle_add — pops the box (takeRetained) so it is freed afterwards.
private let idleSourceFunc: @convention(c) (UnsafeMutableRawPointer?) -> Int32 = { ptr in
    guard let ptr else { return 0 }
    Unmanaged<ClosureBox>.fromOpaque(ptr).takeRetainedValue().closure()
    return 0 // G_SOURCE_REMOVE
}

// Used as the signal handler — borrows the box (takeUnretained).
private let signalCallback: @convention(c) (OpaquePointer?, UnsafeMutableRawPointer?) -> Void = { _, ptr in
    guard let ptr else { return }
    Unmanaged<ClosureBox>.fromOpaque(ptr).takeUnretainedValue().closure()
}

// GClosureNotify: called by GLib when the signal data is no longer needed.
private let signalDestroyNotify: @convention(c) (UnsafeMutableRawPointer?, OpaquePointer?) -> Void = { ptr, _ in
    guard let ptr else { return }
    Unmanaged<ClosureBox>.fromOpaque(ptr).release()
}

// For "delete-event" which must return TRUE to suppress window destruction.
private let deleteEventCallback: @convention(c) (OpaquePointer?, OpaquePointer?, UnsafeMutableRawPointer?) -> Int32 = { _, _, ptr in
    if let ptr { Unmanaged<ClosureBox>.fromOpaque(ptr).takeUnretainedValue().closure() }
    return 1 // TRUE — prevent destroy, we just hide
}

// MARK: - Public helpers

/// Schedule `block` to run on GTK's main thread via GLib idle.
/// Safe to call from any thread (including Swift async task threads).
func scheduleGtkUpdate(_ block: @escaping () -> Void) {
    let box = Unmanaged.passRetained(ClosureBox(block))
    g_idle_add(idleSourceFunc, box.toOpaque())
}

/// Connect a void-returning GTK signal (e.g. "activate", "clicked").
func connectSignal(_ widget: OpaquePointer?, signal: String, block: @escaping () -> Void) {
    let box = Unmanaged.passRetained(ClosureBox(block))
    g_signal_connect_data(
        widget.map(UnsafeMutableRawPointer.init),
        signal,
        unsafeBitCast(signalCallback,      to: GCallback.self),
        box.toOpaque(),
        unsafeBitCast(signalDestroyNotify, to: GClosureNotify.self),
        GConnectFlags(rawValue: 0)
    )
}

/// Connect "delete-event" so the window is hidden rather than destroyed.
func connectDeleteEvent(_ widget: OpaquePointer?, block: @escaping () -> Void) {
    let box = Unmanaged.passRetained(ClosureBox(block))
    g_signal_connect_data(
        widget.map(UnsafeMutableRawPointer.init),
        "delete-event",
        unsafeBitCast(deleteEventCallback, to: GCallback.self),
        box.toOpaque(),
        unsafeBitCast(signalDestroyNotify, to: GClosureNotify.self),
        GConnectFlags(rawValue: 0)
    )
}

// MARK: - OpaquePointer bridging
//
// This GTK/glib version gives GObject types (GtkWidget, GtkLabel, GtkEntry,
// AppIndicator, …) distinct concrete pointer types instead of one shared
// opaque one, so a value stored as OpaquePointer can't be passed directly to,
// say, gtk_label_set_text(_ label: UnsafeMutablePointer<GtkLabel>, ...). The
// rest of this codebase treats every widget/menu/indicator handle as a plain
// OpaquePointer — the simplest common currency across GTK and AppIndicator —
// so these same-named overloads bridge to whatever concrete pointer type each
// underlying call actually expects. They're never ambiguous with the real C
// functions: argument types differ, and each wrapper calls the module-
// qualified original (CGtk.foo / CAppIndicator.foo) internally, so there's no
// self-recursion either.

private func bridge<T>(_ op: OpaquePointer?) -> UnsafeMutablePointer<T>? {
    op.map { UnsafeMutablePointer<T>($0) }
}

// Constructors below are renamed (camelCase) rather than overloaded under the
// C name: with no pointer argument to disambiguate on, only the return type
// would differ from the real function, and Swift can't resolve overloads on
// return type alone at a plain `let x = ...` call site ("ambiguous use of").

@discardableResult
func gtkBoxNew(_ orientation: GtkOrientation, _ spacing: Int32) -> OpaquePointer {
    OpaquePointer(CGtk.gtk_box_new(orientation, spacing))
}

func gtk_box_pack_start(_ box: OpaquePointer?, _ child: OpaquePointer?,
                         _ expand: Int32, _ fill: Int32, _ padding: UInt32) {
    CGtk.gtk_box_pack_start(bridge(box), bridge(child), expand, fill, padding)
}

func gtk_box_set_spacing(_ box: OpaquePointer?, _ spacing: Int32) {
    CGtk.gtk_box_set_spacing(bridge(box), spacing)
}

@discardableResult
func gtkButtonBoxNew(_ orientation: GtkOrientation) -> OpaquePointer {
    OpaquePointer(CGtk.gtk_button_box_new(orientation))
}

func gtk_button_box_set_layout(_ widget: OpaquePointer?, _ style: GtkButtonBoxStyle) {
    CGtk.gtk_button_box_set_layout(bridge(widget), style)
}

@discardableResult
func gtkButtonNewWithLabel(_ label: String) -> OpaquePointer {
    OpaquePointer(CGtk.gtk_button_new_with_label(label))
}

@discardableResult
func gtkCheckButtonNewWithLabel(_ label: String) -> OpaquePointer {
    OpaquePointer(CGtk.gtk_check_button_new_with_label(label))
}

func gtk_container_add(_ container: OpaquePointer?, _ widget: OpaquePointer?) {
    CGtk.gtk_container_add(bridge(container), bridge(widget))
}

func gtk_container_set_border_width(_ container: OpaquePointer?, _ width: UInt32) {
    CGtk.gtk_container_set_border_width(bridge(container), width)
}

func gtk_entry_get_text(_ entry: OpaquePointer?) -> UnsafePointer<CChar>? {
    CGtk.gtk_entry_get_text(bridge(entry))
}

@discardableResult
func gtkEntryNew() -> OpaquePointer {
    OpaquePointer(CGtk.gtk_entry_new())
}

func gtk_entry_set_alignment(_ entry: OpaquePointer?, _ xalign: Float) {
    CGtk.gtk_entry_set_alignment(bridge(entry), xalign)
}

func gtk_entry_set_placeholder_text(_ entry: OpaquePointer?, _ text: String) {
    CGtk.gtk_entry_set_placeholder_text(bridge(entry), text)
}

func gtk_entry_set_text(_ entry: OpaquePointer?, _ text: String) {
    CGtk.gtk_entry_set_text(bridge(entry), text)
}

func gtk_entry_set_visibility(_ entry: OpaquePointer?, _ visible: Int32) {
    CGtk.gtk_entry_set_visibility(bridge(entry), visible)
}

func gtk_entry_set_width_chars(_ entry: OpaquePointer?, _ nChars: Int32) {
    CGtk.gtk_entry_set_width_chars(bridge(entry), nChars)
}

@discardableResult
func gtkLabelNew(_ str: String?) -> OpaquePointer {
    if let str {
        return OpaquePointer(CGtk.gtk_label_new(str))
    }
    return OpaquePointer(CGtk.gtk_label_new(nil))
}

func gtk_label_set_markup(_ label: OpaquePointer?, _ str: String) {
    CGtk.gtk_label_set_markup(bridge(label), str)
}

func gtk_label_set_text(_ label: OpaquePointer?, _ str: String) {
    CGtk.gtk_label_set_text(bridge(label), str)
}

func gtk_label_set_width_chars(_ label: OpaquePointer?, _ nChars: Int32) {
    CGtk.gtk_label_set_width_chars(bridge(label), nChars)
}

func gtk_label_set_xalign(_ label: OpaquePointer?, _ xalign: Float) {
    CGtk.gtk_label_set_xalign(bridge(label), xalign)
}

@discardableResult
func gtkMenuItemNew() -> OpaquePointer {
    OpaquePointer(CGtk.gtk_menu_item_new())
}

@discardableResult
func gtkMenuItemNewWithLabel(_ label: String) -> OpaquePointer {
    OpaquePointer(CGtk.gtk_menu_item_new_with_label(label))
}

func gtk_menu_item_set_label(_ menuItem: OpaquePointer?, _ label: String) {
    CGtk.gtk_menu_item_set_label(bridge(menuItem), label)
}

@discardableResult
func gtkMenuNew() -> OpaquePointer {
    OpaquePointer(CGtk.gtk_menu_new())
}

func gtk_menu_shell_append(_ menuShell: OpaquePointer?, _ child: OpaquePointer?) {
    CGtk.gtk_menu_shell_append(bridge(menuShell), bridge(child))
}

@discardableResult
func gtkSeparatorMenuItemNew() -> OpaquePointer {
    OpaquePointer(CGtk.gtk_separator_menu_item_new())
}

@discardableResult
func gtkSeparatorNew(_ orientation: GtkOrientation) -> OpaquePointer {
    OpaquePointer(CGtk.gtk_separator_new(orientation))
}

func gtk_toggle_button_get_active(_ toggleButton: OpaquePointer?) -> Int32 {
    CGtk.gtk_toggle_button_get_active(bridge(toggleButton))
}

func gtk_toggle_button_set_active(_ toggleButton: OpaquePointer?, _ isActive: Int32) {
    CGtk.gtk_toggle_button_set_active(bridge(toggleButton), isActive)
}

func gtk_widget_hide(_ widget: OpaquePointer?) {
    CGtk.gtk_widget_hide(bridge(widget))
}

func gtk_widget_set_sensitive(_ widget: OpaquePointer?, _ sensitive: Int32) {
    CGtk.gtk_widget_set_sensitive(bridge(widget), sensitive)
}

func gtk_widget_show(_ widget: OpaquePointer?) {
    CGtk.gtk_widget_show(bridge(widget))
}

func gtk_widget_show_all(_ widget: OpaquePointer?) {
    CGtk.gtk_widget_show_all(bridge(widget))
}

@discardableResult
func gtkWindowNew(_ type: GtkWindowType) -> OpaquePointer {
    OpaquePointer(CGtk.gtk_window_new(type))
}

func gtk_window_present(_ window: OpaquePointer?) {
    CGtk.gtk_window_present(bridge(window))
}

func gtk_window_set_default_size(_ window: OpaquePointer?, _ width: Int32, _ height: Int32) {
    CGtk.gtk_window_set_default_size(bridge(window), width, height)
}

func gtk_window_set_resizable(_ window: OpaquePointer?, _ resizable: Int32) {
    CGtk.gtk_window_set_resizable(bridge(window), resizable)
}

func gtk_window_set_title(_ window: OpaquePointer?, _ title: String) {
    CGtk.gtk_window_set_title(bridge(window), title)
}

@discardableResult
func appIndicatorNew(_ id: String, _ iconName: String,
                      _ category: AppIndicatorCategory) -> OpaquePointer {
    OpaquePointer(CAppIndicator.app_indicator_new(id, iconName, category))
}

func app_indicator_set_label(_ indicator: OpaquePointer?, _ label: String, _ guide: String) {
    CAppIndicator.app_indicator_set_label(bridge(indicator), label, guide)
}

func app_indicator_set_menu(_ indicator: OpaquePointer?, _ menu: OpaquePointer?) {
    CAppIndicator.app_indicator_set_menu(bridge(indicator), bridge(menu))
}

func app_indicator_set_status(_ indicator: OpaquePointer?, _ status: AppIndicatorStatus) {
    CAppIndicator.app_indicator_set_status(bridge(indicator), status)
}
