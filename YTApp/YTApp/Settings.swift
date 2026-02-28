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

    static var defaultPlaybackRate: Float {
        get {
            let val = defaults.float(forKey: "defaultPlaybackRate")
            return val > 0 ? val : 2.0
        }
        set { defaults.set(newValue, forKey: "defaultPlaybackRate") }
    }

    static var queueEnabled: Bool {
        get { !defaults.bool(forKey: "queueDisabled") }
        set { defaults.set(!newValue, forKey: "queueDisabled") }
    }

    static var theaterMode: Bool {
        get { defaults.bool(forKey: "theaterMode") }
        set { defaults.set(newValue, forKey: "theaterMode") }
    }

    static var forceTheaterMode: Bool {
        get { defaults.bool(forKey: "forceTheaterMode") }
        set { defaults.set(newValue, forKey: "forceTheaterMode") }
    }

    static var channelSpeeds: [String: Float] {
        get { defaults.dictionary(forKey: "channelSpeeds") as? [String: Float] ?? [:] }
        set { defaults.set(newValue, forKey: "channelSpeeds") }
    }

    static func speedForChannel(_ channel: String) -> Float? {
        guard !channel.isEmpty else { return nil }
        return channelSpeeds[channel]
    }

    static func setSpeedForChannel(_ channel: String, speed: Float) {
        guard !channel.isEmpty else { return }
        var speeds = channelSpeeds
        speeds[channel] = speed
        channelSpeeds = speeds
    }

    static func removeSpeedForChannel(_ channel: String) {
        var speeds = channelSpeeds
        speeds.removeValue(forKey: channel)
        channelSpeeds = speeds
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
