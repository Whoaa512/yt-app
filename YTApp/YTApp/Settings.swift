import Foundation

struct Settings {
    private static let defaults = UserDefaults.standard

    static var suspensionTimeoutMinutes: Int {
        get { max(1, defaults.integer(forKey: "suspensionTimeoutMinutes").nonZero ?? 5) }
        set { defaults.set(newValue, forKey: "suspensionTimeoutMinutes") }
    }

    static var openLinksInNewTab: Bool {
        get { defaults.bool(forKey: "openLinksInNewTab") }
        set { defaults.set(newValue, forKey: "openLinksInNewTab") }
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
