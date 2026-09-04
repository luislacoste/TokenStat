import AppKit

// main.swift always runs on the main thread — inform the compiler
let app = NSApplication.shared
app.setActivationPolicy(.accessory) // No dock icon

// Without a main menu, macOS never resolves Cmd+C/V/X/A key equivalents into
// the standard cut:/copy:/paste:/selectAll: actions — text fields in Settings
// would be unable to paste. A minimal Edit menu is enough to fix that.
let mainMenu = NSMenu()

let appMenuItem = NSMenuItem()
mainMenu.addItem(appMenuItem)
let appMenu = NSMenu()
appMenuItem.submenu = appMenu
appMenu.addItem(NSMenuItem(title: "Quit TokenStat",
                           action: #selector(NSApplication.terminate(_:)),
                           keyEquivalent: "q"))

let editMenuItem = NSMenuItem()
mainMenu.addItem(editMenuItem)
let editMenu = NSMenu(title: "Edit")
editMenuItem.submenu = editMenu
editMenu.addItem(NSMenuItem(title: "Cut",        action: #selector(NSText.cut(_:)),       keyEquivalent: "x"))
editMenu.addItem(NSMenuItem(title: "Copy",       action: #selector(NSText.copy(_:)),      keyEquivalent: "c"))
editMenu.addItem(NSMenuItem(title: "Paste",      action: #selector(NSText.paste(_:)),     keyEquivalent: "v"))
editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

app.mainMenu = mainMenu

let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
