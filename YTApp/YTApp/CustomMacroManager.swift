import Foundation

/// Action a macro performs when triggered.
enum MacroAction: Codable, Equatable {
    case clickSelector(String)       // Click a CSS selector
    case evaluateJS(String)          // Run arbitrary JS
    case navigate(String)            // Load a URL in the active tab

    // Codable
    enum CodingKeys: String, CodingKey { case type, value }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .clickSelector(let v): try c.encode("click", forKey: .type); try c.encode(v, forKey: .value)
        case .evaluateJS(let v):    try c.encode("js", forKey: .type);    try c.encode(v, forKey: .value)
        case .navigate(let v):      try c.encode("nav", forKey: .type);   try c.encode(v, forKey: .value)
        }
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        let value = try c.decode(String.self, forKey: .value)
        switch type {
        case "click": self = .clickSelector(value)
        case "js":    self = .evaluateJS(value)
        case "nav":   self = .navigate(value)
        default:      self = .evaluateJS(value)
        }
    }

    var typeLabel: String {
        switch self {
        case .clickSelector: return "Click"
        case .evaluateJS:    return "JS"
        case .navigate:      return "Navigate"
        }
    }
    var value: String {
        switch self {
        case .clickSelector(let v), .evaluateJS(let v), .navigate(let v): return v
        }
    }
}

/// A single user-defined keyboard macro.
struct UserMacro: Codable, Identifiable {
    var id: String { key }
    var key: String            // single char like "x", or combo like "gp"
    var name: String           // human label
    var action: MacroAction
    var urlPattern: String?    // optional — only fire on URLs matching this substring
}

/// Manages user macros with UserDefaults persistence.
class CustomMacroManager {
    static let shared = CustomMacroManager()
    private let storageKey = "userMacros"
    private(set) var macros: [UserMacro] = []

    private init() { load() }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([UserMacro].self, from: data) else {
            macros = []
            return
        }
        macros = decoded
    }

    func save() {
        if let data = try? JSONEncoder().encode(macros) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    func add(_ macro: UserMacro) {
        // Replace if same key exists
        macros.removeAll { $0.key == macro.key }
        macros.append(macro)
        save()
    }

    func remove(key: String) {
        macros.removeAll { $0.key == key }
        save()
    }

    func macro(forKey key: String, url: String? = nil) -> UserMacro? {
        macros.first { m in
            m.key == key && (m.urlPattern == nil || m.urlPattern!.isEmpty || (url?.contains(m.urlPattern!) == true))
        }
    }
}
