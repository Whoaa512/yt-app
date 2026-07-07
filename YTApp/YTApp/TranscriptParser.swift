import Foundation

struct TranscriptCue: Equatable {
    let start: Double
    let text: String
}

/// Parses YouTube timedtext JSON3 payloads into cues for the transcript
/// sidebar. Pure logic — covered by Tests/TranscriptParserTests.
enum TranscriptParser {
    static func parse(json3: String) -> [TranscriptCue] {
        guard let data = json3.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = root["events"] as? [[String: Any]] else { return [] }

        return events.compactMap { event in
            guard let startMs = event["tStartMs"] as? Double,
                  let segs = event["segs"] as? [[String: Any]] else { return nil }
            let text = segs.compactMap { $0["utf8"] as? String }.joined()
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return nil }
            return TranscriptCue(start: startMs / 1000.0, text: text)
        }
    }

    static func timestamp(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    static func filter(cues: [TranscriptCue], query: String) -> [TranscriptCue] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return cues }
        return cues.filter { $0.text.localizedCaseInsensitiveContains(q) }
    }

    /// Index of the cue active at `time` (last cue whose start <= time).
    static func cueIndex(at time: Double, in cues: [TranscriptCue]) -> Int? {
        guard !cues.isEmpty else { return nil }
        var idx: Int?
        for (i, cue) in cues.enumerated() {
            if cue.start <= time { idx = i } else { break }
        }
        return idx
    }
}
