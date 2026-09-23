import Foundation
import Glibc
import CGtk
import CAppIndicator

// Single-instance guard — avoids a duplicate tray icon if TokenStat is
// launched again (e.g. from the app grid) while an instance from autostart
// is already running. flock is released automatically when the process exits.
let lockDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".cache/tokenstat").path
try? FileManager.default.createDirectory(atPath: lockDir, withIntermediateDirectories: true)
let lockFD = open(lockDir + "/tokenstat.lock", O_CREAT | O_RDWR, 0o644)
if lockFD == -1 || flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
    FileHandle.standardError.write("TokenStat is already running.\n".data(using: .utf8)!)
    exit(0)
}

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
