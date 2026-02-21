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

    static var playbackRate: Float {
        get {
            let val = defaults.float(forKey: "playbackRate")
            return val > 0 ? val : 1.0
        }
        set { defaults.set(newValue, forKey: "playbackRate") }
    }

    static var theaterMode: Bool {
        get { defaults.bool(forKey: "theaterMode") }
        set { defaults.set(newValue, forKey: "theaterMode") }
    }

    static var forceTheaterMode: Bool {
        get { defaults.bool(forKey: "forceTheaterMode") }
        set { defaults.set(newValue, forKey: "forceTheaterMode") }
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
