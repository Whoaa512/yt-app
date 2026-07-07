import Foundation

/// Extracts YouTube video ids so playback positions survive URL variants
/// (playlist params, timestamps, youtu.be links). Covered by Tests/VideoURLTests.
enum VideoURL {
    static func videoId(from urlString: String) -> String? {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespaces)),
              let host = url.host else { return nil }

        var candidate: String?
        if host.contains("youtu.be") {
            candidate = url.pathComponents.dropFirst().first
        } else if url.path == "/watch" {
            candidate = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "v" })?.value
        } else if url.pathComponents.count >= 3, url.pathComponents[1] == "shorts" {
            candidate = url.pathComponents[2]
        }

        guard let id = candidate, id.count == 11,
              id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return nil }
        return id
    }
}
