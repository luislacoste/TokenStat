import Foundation
import CGtk
import CAppIndicator

// Initialize GTK before any GTK calls.
var argc = CommandLine.argc
// gtk_init expects char*** with an optional middle pointer level;
// CommandLine.unsafeArgv is non-optional there, so re-type explicitly.
var argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>? = CommandLine.unsafeArgv
gtk_init(&argc, &argv)

// TrayController sets up the AppIndicator, connects ClaudeService, and starts polling.
let tray = TrayController()

// Block the main thread with GTK's event loop.
// Swift async tasks run on the cooperative thread pool (background threads);
// GTK UI updates are marshalled back via g_idle_add (see GtkHelpers.scheduleGtkUpdate).
gtk_main()
