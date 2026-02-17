import Cocoa
import WebKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var mainWindowController: MainWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize history database
        HistoryManager.shared.setup()

        mainWindowController = MainWindowController()
        mainWindowController.showWindow(nil)
        mainWindowController.window?.makeKeyAndOrderFront(nil)

        // Re-apply menus after launch to ensure they stick
        mainWindowController.setupMenus()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        mainWindowController?.saveWindowState()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}
