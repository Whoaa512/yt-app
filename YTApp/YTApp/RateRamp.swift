import Foundation

/// Generates smooth playback-rate transitions so speed changes glide instead
/// of jumping. Pure logic — covered by Tests/RateRampTests.
enum RateRamp {
    static let stepCount = 8
    static let durationMs = 280

    /// Ease-out interpolated rate values from `from` to `to`, ending exactly at `to`.
    static func steps(from: Float, to: Float) -> [Float] {
        guard abs(to - from) > 0.001 else { return [to] }
        return (1...stepCount).map { i in
            let t = Float(i) / Float(stepCount)
            let eased = 1 - (1 - t) * (1 - t)
            let value = from + (to - from) * eased
            return i == stepCount ? to : (value * 1000).rounded() / 1000
        }
    }

    /// JS that ramps the page's <video> rate using setTimeout steps.
    /// Cancels any in-flight ramp via a window-scoped token.
    static func rampJS(from: Float, to: Float) -> String {
        let values = steps(from: from, to: to)
        let interval = durationMs / max(1, values.count)
        let list = values.map { String(format: "%.3f", $0) }.joined(separator: ",")
        return """
        (function() {
            const v = document.querySelector('video');
            if (!v) return;
            const token = (window.__ytRampToken = (window.__ytRampToken || 0) + 1);
            const rates = [\(list)];
            rates.forEach(function(r, i) {
                setTimeout(function() {
                    if (window.__ytRampToken !== token) return;
                    v.playbackRate = r;
                }, i * \(interval));
            });
        })()
        """
    }
}
