import CGtk

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
