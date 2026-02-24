import Cocoa
import WebKit

protocol KeyboardShortcutDelegate: AnyObject {
    func shortcutNewTab()
    func shortcutCloseTab()
    func shortcutNextTab()
    func shortcutPrevTab()
    func shortcutFocusAddressBar()
    func shortcutGoBack()
    func shortcutGoForward()
    func shortcutRefresh()
    func shortcutPlayPause()
    func shortcutToggleQueue()
    func shortcutShowHistory()
    func shortcutShowHelp()
    func shortcutShowLinkHints(newTab: Bool)
    func shortcutScrollTop()
    func shortcutScrollBottom()
    func shortcutStartElementPicker()
    func shortcutToggleSuspendTab()
    func shortcutSuspendOtherTabs()
    func shortcutUnsuspendAllTabs()
    func shortcutActiveWebView() -> WKWebView?
    func shortcutActiveURL() -> String?
}

/// Handles Vimium-style keyboard shortcuts via a local event monitor.
/// Only fires when the WebView (not a text field) has focus.
class KeyboardShortcutHandler {
    weak var delegate: KeyboardShortcutDelegate?
    private var monitor: Any?
    private var pendingPrefix: String?
    private var prefixTimer: Timer?

    struct Shortcut {
        let key: String
        let label: String
        let category: String
    }

    /// Built-in shortcuts for display in help modal.
    static let builtInShortcuts: [Shortcut] = [
        // Navigation
        Shortcut(key: "H", label: "Go back", category: "Navigation"),
        Shortcut(key: "L", label: "Go forward", category: "Navigation"),
        Shortcut(key: "r", label: "Reload page", category: "Navigation"),
        Shortcut(key: "o", label: "Focus address bar", category: "Navigation"),
        Shortcut(key: "gg", label: "Scroll to top", category: "Navigation"),
        Shortcut(key: "G", label: "Scroll to bottom", category: "Navigation"),
        // Tabs
        Shortcut(key: "t", label: "New tab", category: "Tabs"),
        Shortcut(key: "x", label: "Close tab", category: "Tabs"),
        Shortcut(key: "J", label: "Next tab", category: "Tabs"),
        Shortcut(key: "K", label: "Previous tab", category: "Tabs"),
        // Link Hints
        Shortcut(key: "f", label: "Open link hints", category: "Link Hints"),
        Shortcut(key: "F", label: "Open link in new tab", category: "Link Hints"),
        // Playback
        Shortcut(key: "k", label: "Play / pause", category: "Playback"),
        // Panels
        Shortcut(key: "q", label: "Toggle queue sidebar", category: "Panels"),
        Shortcut(key: "gh", label: "Show history", category: "Panels"),
        // Other
        // Suspension
        Shortcut(key: "gs", label: "Suspend / unsuspend tab", category: "Tabs"),
        Shortcut(key: "gS", label: "Suspend other tabs", category: "Tabs"),
        Shortcut(key: "gU", label: "Unsuspend all tabs", category: "Tabs"),
        Shortcut(key: "?", label: "Show keyboard shortcuts", category: "Other"),
        Shortcut(key: "gm", label: "Start element picker (create macro)", category: "Other"),
    ]

    func start() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            return self.handleKeyDown(event) ? nil : event
        }
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }

    deinit { stop() }

    /// Returns true if the event was consumed.
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection([.command, .control, .option])

        // Ctrl+Tab / Ctrl+Shift+Tab for tab switching
        if mods.contains(.control) && event.keyCode == 48 {
            if event.modifierFlags.contains(.shift) {
                delegate?.shortcutPrevTab()
            } else {
                delegate?.shortcutNextTab()
            }
            return true
        }

        // Don't intercept other modifier key combos — those go to menus
        if !mods.isEmpty { return false }

        // Don't intercept when a text field/input has focus
        if let responder = event.window?.firstResponder {
            if responder is NSTextView,
               let fieldEditor = (responder as? NSTextView),
               fieldEditor.isFieldEditor || fieldEditor.superview is NSTextField {
                return false
            }
        }

        // Check if link hints are active — let the JS handle everything
        if let wv = delegate?.shortcutActiveWebView() {
            var hintsActive = false
            let sem = DispatchSemaphore(value: 0)
            wv.evaluateJavaScript("window.__ytLinkHintsActive ? window.__ytLinkHintsActive() : false") { result, _ in
                hintsActive = (result as? Bool) ?? false
                sem.signal()
            }
            _ = sem.wait(timeout: .now() + 0.05)
            if hintsActive { return false }
        }

        guard let chars = event.charactersIgnoringModifiers, !chars.isEmpty else { return false }
        let ch = chars

        // Handle prefix sequences (g + next char)
        if let prefix = pendingPrefix {
            prefixTimer?.invalidate()
            pendingPrefix = nil

            let seq = prefix + ch
            // Check custom macros first
            if let macro = CustomMacroManager.shared.macro(forKey: seq, url: delegate?.shortcutActiveURL()) {
                executeMacro(macro)
                return true
            }
            switch seq {
            case "gg": delegate?.shortcutScrollTop(); return true
            case "gh": delegate?.shortcutShowHistory(); return true
            case "gm": delegate?.shortcutStartElementPicker(); return true
            case "gs": delegate?.shortcutToggleSuspendTab(); return true
            case "gS": delegate?.shortcutSuspendOtherTabs(); return true
            case "gU": delegate?.shortcutUnsuspendAllTabs(); return true
            default: return false
            }
        }

        // Start prefix
        if ch == "g" {
            pendingPrefix = "g"
            prefixTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                self?.pendingPrefix = nil
            }
            return true
        }

        // Check custom macros for single-char keys
        if let macro = CustomMacroManager.shared.macro(forKey: ch, url: delegate?.shortcutActiveURL()) {
            executeMacro(macro)
            return true
        }

        // Check plugin JS shortcuts (async, but we need sync here — fire and don't block)
        // Plugin shortcuts are checked in JS first via the link hints pattern
        if let wv = delegate?.shortcutActiveWebView() {
            var pluginHandled = false
            let sem = DispatchSemaphore(value: 0)
            wv.evaluateJavaScript("window.__ytAppPluginShortcut && window.__ytAppPluginShortcut('\(ch.replacingOccurrences(of: "'", with: "\\'"))')") { result, _ in
                pluginHandled = (result as? Bool) ?? false
                sem.signal()
            }
            _ = sem.wait(timeout: .now() + 0.05)
            if pluginHandled { return true }
        }

        // Built-in single-key shortcuts
        switch ch {
        case "?": delegate?.shortcutShowHelp(); return true
        case "f": delegate?.shortcutShowLinkHints(newTab: false); return true
        case "F": delegate?.shortcutShowLinkHints(newTab: true); return true
        case "t": delegate?.shortcutNewTab(); return true
        case "x": delegate?.shortcutCloseTab(); return true
        case "J": delegate?.shortcutNextTab(); return true
        case "K": delegate?.shortcutPrevTab(); return true
        case "o": delegate?.shortcutFocusAddressBar(); return true
        case "H": delegate?.shortcutGoBack(); return true
        case "L": delegate?.shortcutGoForward(); return true
        case "r": delegate?.shortcutRefresh(); return true
        case "k": delegate?.shortcutPlayPause(); return true
        case "q": delegate?.shortcutToggleQueue(); return true
        case "G": delegate?.shortcutScrollBottom(); return true
        default: return false
        }
    }

    private func executeMacro(_ macro: UserMacro) {
        guard let wv = delegate?.shortcutActiveWebView() else { return }
        switch macro.action {
        case .clickSelector(let sel):
            let escaped = sel.replacingOccurrences(of: "'", with: "\\'")
            wv.evaluateJavaScript("document.querySelector('\(escaped)')?.click()")
        case .evaluateJS(let js):
            wv.evaluateJavaScript(js)
        case .navigate(let url):
            if let u = URL(string: url) {
                wv.load(URLRequest(url: u))
            }
        }
    }
}
