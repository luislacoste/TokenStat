import AppKit

// main.swift always runs on the main thread — inform the compiler
let app = NSApplication.shared
app.setActivationPolicy(.accessory) // No dock icon
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
