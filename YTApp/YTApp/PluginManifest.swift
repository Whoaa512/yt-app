import Foundation

/// Manifest for a YTApp plugin, loaded from manifest.json.
struct PluginManifest: Codable {
    let name: String
    let version: String?
    let description: String?
    let author: String?

    /// Content scripts to inject into pages.
    let contentScripts: [ContentScript]?

    /// CSS files to inject.
    let styles: [String]?

    /// Keyboard shortcuts this plugin registers.
    let shortcuts: [String: ShortcutAction]?

    /// Events this plugin wants to receive.
    let permissions: [String]?

    /// Plugin settings schema (for UI).
    let settings: [SettingDef]?

    enum CodingKeys: String, CodingKey {
        case name, version, description, author
        case contentScripts = "content_scripts"
        case styles, shortcuts, permissions, settings
    }

    struct ContentScript: Codable {
        let js: [String]?
        let css: [String]?
        let injectAt: String?       // "document_start" | "document_end" (default)
        let urlPatterns: [String]?   // glob patterns, nil = all youtube pages

        enum CodingKeys: String, CodingKey {
            case js, css
            case injectAt = "inject_at"
            case urlPatterns = "url_patterns"
        }
    }

    struct ShortcutAction: Codable {
        let action: String           // "click" | "js" | "navigate" | "message"
        let value: String            // selector, JS code, URL, or message name
        let label: String?           // human-readable description
        let urlPattern: String?      // optional URL filter
    }

    struct SettingDef: Codable {
        let key: String
        let label: String
        let type: String             // "bool" | "string" | "number" | "select"
        let defaultValue: String?
        let options: [String]?       // for "select" type

        enum CodingKeys: String, CodingKey {
            case key, label, type
            case defaultValue = "default"
            case options
        }
    }
}

/// A loaded plugin with its manifest and resolved file paths.
struct LoadedPlugin {
    let manifest: PluginManifest
    let directory: URL
    var enabled: Bool

    /// Unique identifier derived from directory name.
    var id: String { directory.lastPathComponent }

    func resolvedJS() -> [(source: String, injectAt: String)] {
        var scripts: [(String, String)] = []
        for cs in manifest.contentScripts ?? [] {
            let timing = cs.injectAt ?? "document_end"
            for jsFile in cs.js ?? [] {
                let url = directory.appendingPathComponent(jsFile)
                if let source = try? String(contentsOf: url, encoding: .utf8) {
                    scripts.append((source, timing))
                }
            }
        }
        return scripts
    }

    func resolvedCSS() -> [String] {
        var allCSS: [String] = []
        // Top-level styles
        for cssFile in manifest.styles ?? [] {
            let url = directory.appendingPathComponent(cssFile)
            if let source = try? String(contentsOf: url, encoding: .utf8) {
                allCSS.append(source)
            }
        }
        // Content script CSS
        for cs in manifest.contentScripts ?? [] {
            for cssFile in cs.css ?? [] {
                let url = directory.appendingPathComponent(cssFile)
                if let source = try? String(contentsOf: url, encoding: .utf8) {
                    allCSS.append(source)
                }
            }
        }
        return allCSS
    }
}
