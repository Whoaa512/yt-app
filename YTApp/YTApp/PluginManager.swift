import Foundation
import WebKit

protocol PluginManagerDelegate: AnyObject {
    func pluginManager(_ manager: PluginManager, didReceiveNotification message: String, type: String)
    func pluginManager(_ manager: PluginManager, openTab url: URL)
    func pluginManager(_ manager: PluginManager, navigate url: URL)
    func pluginManager(_ manager: PluginManager, queueAdd videoId: String, title: String, channel: String, duration: String)
    func pluginManagerQueueClear(_ manager: PluginManager)
    func pluginManagerQueuePlayNext(_ manager: PluginManager)
    func pluginManager(_ manager: PluginManager, setRate rate: Float)
    func pluginManagerPluginsDidReload(_ manager: PluginManager)
}

/// Discovers, loads, and manages YTApp plugins.
/// Modeled after pi's extension system: directory-based, hot-reloadable, event-driven.
class PluginManager {
    static let shared = PluginManager()
    weak var delegate: PluginManagerDelegate?

    private(set) var plugins: [LoadedPlugin] = []
    private var fsEventStream: FSEventStreamRef?
    private let storagePrefix = "plugin."

    /// The JS source for YTAppAPI.js (loaded from bundle once).
    private let apiJS: String = {
        if let url = Bundle.main.url(forResource: "YTAppAPI", withExtension: "js"),
           let src = try? String(contentsOf: url) {
            return src
        }
        return ""
    }()

    // MARK: - Discovery

    /// Plugin directories, searched in order.
    static var pluginDirectories: [URL] {
        var dirs: [URL] = []
        // Global: ~/.ytapp/plugins/
        let home = FileManager.default.homeDirectoryForCurrentUser
        dirs.append(home.appendingPathComponent(".ytapp/plugins"))
        return dirs
    }

    func discoverAndLoad() {
        plugins = []
        for dir in Self.pluginDirectories {
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
            ) else { continue }

            for entry in entries {
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: entry.path, isDirectory: &isDir)
                guard isDir.boolValue else { continue }

                let manifestURL = entry.appendingPathComponent("manifest.json")
                guard let data = try? Data(contentsOf: manifestURL),
                      let manifest = try? JSONDecoder().decode(PluginManifest.self, from: data) else {
                    print("[PluginManager] Skipping \(entry.lastPathComponent): invalid manifest.json")
                    continue
                }

                let enabled = UserDefaults.standard.bool(forKey: enabledKey(for: entry.lastPathComponent))
                    || !UserDefaults.standard.contains(key: enabledKey(for: entry.lastPathComponent))
                plugins.append(LoadedPlugin(manifest: manifest, directory: entry, enabled: enabled))
                print("[PluginManager] Loaded plugin: \(manifest.name) v\(manifest.version ?? "?") [\(enabled ? "on" : "off")]")
            }
        }
    }

    func reload() {
        discoverAndLoad()
        delegate?.pluginManagerPluginsDidReload(self)
    }

    // MARK: - Enable / Disable

    func setEnabled(_ enabled: Bool, pluginId: String) {
        if let idx = plugins.firstIndex(where: { $0.id == pluginId }) {
            plugins[idx].enabled = enabled
            UserDefaults.standard.set(enabled, forKey: enabledKey(for: pluginId))
        }
    }

    private func enabledKey(for pluginId: String) -> String {
        "plugin.enabled.\(pluginId)"
    }

    // MARK: - Script Injection

    /// Returns all WKUserScripts to inject (API + enabled plugin scripts).
    func userScripts() -> [WKUserScript] {
        var scripts: [WKUserScript] = []

        // 1. YTAppAPI.js — always first, at document start
        scripts.append(WKUserScript(source: apiJS, injectionTime: .atDocumentStart, forMainFrameOnly: true))

        // 2. Plugin scripts
        for plugin in plugins where plugin.enabled {
            // CSS injection wrapper
            for css in plugin.resolvedCSS() {
                let escaped = css.replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "`", with: "\\`")
                    .replacingOccurrences(of: "$", with: "\\$")
                let cssJS = """
                (function(){
                    var s = document.createElement('style');
                    s.id = 'ytapp-plugin-\(plugin.id)';
                    s.textContent = `\(escaped)`;
                    (document.head || document.documentElement).appendChild(s);
                })();
                """
                scripts.append(WKUserScript(source: cssJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
            }

            // JS injection with scoped plugin context
            for (source, timing) in plugin.resolvedJS() {
                let wrapped = """
                (function(){
                    window.YTApp._currentPlugin = '\(plugin.id)';
                    var plugin = window.YTApp.scoped('\(plugin.id)');
                    \(source)
                })();
                """
                let time: WKUserScriptInjectionTime = timing == "document_start" ? .atDocumentStart : .atDocumentEnd
                scripts.append(WKUserScript(source: wrapped, injectionTime: time, forMainFrameOnly: true))
            }

            // Manifest-declared shortcuts
            if let shortcuts = plugin.manifest.shortcuts {
                for (key, action) in shortcuts {
                    let js: String
                    switch action.action {
                    case "click":
                        let sel = action.value.replacingOccurrences(of: "'", with: "\\'")
                        js = "document.querySelector('\(sel)')?.click()"
                    case "js":
                        js = action.value
                    case "navigate":
                        js = "window.location.href = '\(action.value.replacingOccurrences(of: "'", with: "\\'"))'"
                    default:
                        js = ""
                    }
                    if !js.isEmpty {
                        let label = action.label ?? "\(plugin.manifest.name): \(key)"
                        let escaped = js.replacingOccurrences(of: "\\", with: "\\\\")
                            .replacingOccurrences(of: "'", with: "\\'")
                            .replacingOccurrences(of: "\n", with: "\\n")
                        let shortcutJS = """
                        window.YTApp.registerShortcut('\(key)', '\(label)', function(){ \(escaped.replacingOccurrences(of: "\\\\n", with: ";")) }, '\(plugin.id)');
                        """
                        scripts.append(WKUserScript(source: shortcutJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
                    }
                }
            }
        }

        return scripts
    }

    // MARK: - Message Handling (from JS pluginBridge)

    func handleMessage(_ body: Any, webView: WKWebView) {
        guard let str = body as? String,
              let data = str.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        let payload = json["payload"] as? [String: Any] ?? [:]
        let callId = json["callId"] as? Int

        switch type {
        case "notify":
            let msg = payload["message"] as? String ?? ""
            let notifType = payload["type"] as? String ?? "info"
            delegate?.pluginManager(self, didReceiveNotification: msg, type: notifType)

        case "openTab":
            if let urlStr = payload["url"] as? String, let url = URL(string: urlStr) {
                delegate?.pluginManager(self, openTab: url)
            }

        case "navigate":
            if let urlStr = payload["url"] as? String, let url = URL(string: urlStr) {
                delegate?.pluginManager(self, navigate: url)
            }

        case "queueAdd":
            let videoId = payload["videoId"] as? String ?? ""
            let title = payload["title"] as? String ?? ""
            let channel = payload["channel"] as? String ?? ""
            let duration = payload["duration"] as? String ?? ""
            delegate?.pluginManager(self, queueAdd: videoId, title: title, channel: channel, duration: duration)

        case "queueClear":
            delegate?.pluginManagerQueueClear(self)

        case "queuePlayNext":
            delegate?.pluginManagerQueuePlayNext(self)

        case "setRate":
            if let rate = payload["rate"] as? Float ?? (payload["rate"] as? Double).map({ Float($0) }) {
                delegate?.pluginManager(self, setRate: rate)
            }

        case "storageGet":
            if let callId = callId, let pluginId = payload["pluginId"] as? String, let key = payload["key"] as? String {
                let fullKey = "\(storagePrefix)\(pluginId).\(key)"
                let value = UserDefaults.standard.object(forKey: fullKey)
                resolveCall(callId, result: value, webView: webView)
            }

        case "storageSet":
            if let pluginId = payload["pluginId"] as? String, let key = payload["key"] as? String {
                let fullKey = "\(storagePrefix)\(pluginId).\(key)"
                UserDefaults.standard.set(payload["value"], forKey: fullKey)
            }

        case "storageGetAll":
            if let callId = callId, let pluginId = payload["pluginId"] as? String {
                let prefix = "\(storagePrefix)\(pluginId)."
                var result: [String: Any] = [:]
                for (key, value) in UserDefaults.standard.dictionaryRepresentation() {
                    if key.hasPrefix(prefix) {
                        let shortKey = String(key.dropFirst(prefix.count))
                        result[shortKey] = value
                    }
                }
                resolveCall(callId, result: result, webView: webView)
            }

        case "registerCommand":
            // Commands are tracked in JS; nothing to do Swift-side yet
            break

        default:
            print("[PluginManager] Unknown message type: \(type)")
        }
    }

    private func resolveCall(_ callId: Int, result: Any?, webView: WKWebView) {
        if let result = result,
           let data = try? JSONSerialization.data(withJSONObject: result),
           let json = String(data: data, encoding: .utf8) {
            webView.evaluateJavaScript("window.__ytAppResolveCall(\(callId), \(json))")
        } else if let result = result as? String {
            let escaped = result.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
            webView.evaluateJavaScript("window.__ytAppResolveCall(\(callId), '\(escaped)')")
        } else {
            webView.evaluateJavaScript("window.__ytAppResolveCall(\(callId), undefined)")
        }
    }

    // MARK: - Dispatch Events to Plugins

    func dispatchEvent(_ event: String, data: [String: Any], webView: WKWebView?) {
        guard let wv = webView else { return }
        if let jsonData = try? JSONSerialization.data(withJSONObject: data),
           let json = String(data: jsonData, encoding: .utf8) {
            wv.evaluateJavaScript("window.__ytAppDispatchEvent && window.__ytAppDispatchEvent('\(event)', \(json))")
        }
    }

    // MARK: - FSEvents Hot Reload

    func startWatching() {
        let paths = Self.pluginDirectories.map { $0.path } as CFArray
        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        guard let stream = FSEventStreamCreate(
            nil,
            { (_, info, numEvents, eventPaths, _, _) in
                guard let info = info else { return }
                let mgr = Unmanaged<PluginManager>.fromOpaque(info).takeUnretainedValue()
                DispatchQueue.main.async {
                    print("[PluginManager] File changes detected, reloading plugins...")
                    mgr.reload()
                }
            },
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0, // debounce 1s
            UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        ) else { return }

        fsEventStream = stream
        FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        FSEventStreamStart(stream)
    }

    func stopWatching() {
        if let stream = fsEventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            fsEventStream = nil
        }
    }

    // MARK: - Ensure Directories

    func ensurePluginDirectories() {
        for dir in Self.pluginDirectories {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Plugin Shortcuts for KeyboardHandler

    /// Check if any plugin JS-registered shortcut handles this key.
    func checkPluginShortcut(key: String, webView: WKWebView?, completion: @escaping (Bool) -> Void) {
        guard let wv = webView else { completion(false); return }
        wv.evaluateJavaScript("window.__ytAppPluginShortcut && window.__ytAppPluginShortcut('\(key)')") { result, _ in
            completion((result as? Bool) ?? false)
        }
    }
}

// MARK: - UserDefaults helper

extension UserDefaults {
    func contains(key: String) -> Bool {
        object(forKey: key) != nil
    }
}
