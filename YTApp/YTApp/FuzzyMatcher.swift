import Foundation

/// Subsequence fuzzy matcher for the command palette.
/// Scoring: consecutive runs and word-boundary hits score high, early matches
/// beat late ones. Pure logic — covered by Tests/FuzzyMatcherTests.
enum FuzzyMatcher {
    struct Match {
        let score: Int
        let ranges: [Range<String.Index>]
    }

    struct Ranked<T> {
        let item: T
        let match: Match
    }

    static func match(query: String, in text: String) -> Match? {
        if query.isEmpty { return Match(score: 0, ranges: []) }

        let q = Array(query.lowercased())
        let t = Array(text.lowercased())
        var ranges: [Range<Int>] = []
        var score = 0
        var qi = 0
        var lastMatchIdx = -2

        for (ti, ch) in t.enumerated() {
            guard qi < q.count else { break }
            if q[qi] == " " && ch != " " {
                // Treat query spaces as soft separators
                while qi < q.count && q[qi] == " " { qi += 1 }
                guard qi < q.count else { break }
            }
            guard ch == q[qi] else { continue }

            var charScore = 1
            if ti == lastMatchIdx + 1 { charScore += 12 }
            let isBoundary = ti == 0 || t[ti - 1] == " " || t[ti - 1] == "-" || t[ti - 1] == "/"
            if isBoundary { charScore += 10 }
            charScore += max(0, 6 - ti / 4)
            score += charScore

            if let last = ranges.last, last.upperBound == ti {
                ranges[ranges.count - 1] = last.lowerBound..<(ti + 1)
            } else {
                ranges.append(ti..<(ti + 1))
            }
            lastMatchIdx = ti
            qi += 1
        }

        while qi < q.count && q[qi] == " " { qi += 1 }
        guard qi == q.count else { return nil }

        let stringRanges = ranges.map { r -> Range<String.Index> in
            let lo = text.index(text.startIndex, offsetBy: r.lowerBound)
            let hi = text.index(text.startIndex, offsetBy: r.upperBound)
            return lo..<hi
        }
        return Match(score: score, ranges: stringRanges)
    }

    static func rank<T>(query: String, items: [T], text: (T) -> String) -> [Ranked<T>] {
        items.compactMap { item in
            match(query: query, in: text(item)).map { Ranked(item: item, match: $0) }
        }
        .sorted { $0.match.score > $1.match.score }
    }
}
