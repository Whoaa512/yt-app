import Foundation
import Cocoa

struct URLRouter {
    static let allowedDomains = [
        "youtube.com",
        "youtu.be",
        "google.com",
        "gstatic.com",
        "googleapis.com",
        "googleusercontent.com",
        "googlevideo.com",
        "ggpht.com",
        "ytimg.com",
    ]

    static func isAllowed(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return allowedDomains.contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    static func openInDefaultBrowser(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    static func resolveInput(_ input: String) -> URL {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme != nil, url.host != nil {
            return url
        }
        if trimmed.contains(".") && !trimmed.contains(" "),
           let url = URL(string: "https://\(trimmed)") {
            return url
        }
        let query = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        return URL(string: "https://www.youtube.com/results?search_query=\(query)")!
    }
}
