import Foundation
import CGtk
import CAppIndicator

// Initialize GTK before any GTK calls.
var argc = CommandLine.argc
var argv = CommandLine.unsafeArgv
gtk_init(&argc, &argv)

// TrayController sets up the AppIndicator, connects ClaudeService, and starts polling.
let tray = TrayController()

// Block the main thread with GTK's event loop.
// Swift async tasks run on the cooperative thread pool (background threads);
// GTK UI updates are marshalled back via g_idle_add (see GtkHelpers.scheduleGtkUpdate).
gtk_main()
