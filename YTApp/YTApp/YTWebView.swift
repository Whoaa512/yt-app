import Cocoa
import WebKit

protocol YTWebViewContextMenuDelegate: AnyObject {
    func ytWebViewSummarizeVideo(url: String)
    func ytWebViewDownloadVideo(url: String)
}

class YTWebView: WKWebView {
    weak var contextMenuDelegate: YTWebViewContextMenuDelegate?

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)

        let summarizeItem = NSMenuItem(title: "Summarize Video", action: #selector(summarizeFromMenu(_:)), keyEquivalent: "")
        summarizeItem.target = self
        summarizeItem.image = NSImage(systemSymbolName: "text.document", accessibilityDescription: nil)

        let downloadItem = NSMenuItem(title: "Download Video", action: #selector(downloadFromMenu(_:)), keyEquivalent: "")
        downloadItem.target = self
        downloadItem.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)

        menu.insertItem(.separator(), at: 0)
        menu.insertItem(downloadItem, at: 0)
        menu.insertItem(summarizeItem, at: 0)
    }

    @objc private func downloadFromMenu(_ sender: NSMenuItem) {
        evaluateJavaScript("window.__ytGetSummarizeVideoUrl && window.__ytGetSummarizeVideoUrl()") { [weak self] result, _ in
            guard let self else { return }
            if let videoUrl = result as? String, !videoUrl.isEmpty {
                self.contextMenuDelegate?.ytWebViewDownloadVideo(url: videoUrl)
                return
            }
            if let pageUrl = self.url?.absoluteString, pageUrl.contains("youtube.com/watch") {
                self.contextMenuDelegate?.ytWebViewDownloadVideo(url: pageUrl)
            }
        }
    }

    @objc private func summarizeFromMenu(_ sender: NSMenuItem) {
        evaluateJavaScript("window.__ytGetSummarizeVideoUrl && window.__ytGetSummarizeVideoUrl()") { [weak self] result, _ in
            guard let self else { return }
            if let videoUrl = result as? String, !videoUrl.isEmpty {
                self.contextMenuDelegate?.ytWebViewSummarizeVideo(url: videoUrl)
                return
            }
            if let pageUrl = self.url?.absoluteString, pageUrl.contains("youtube.com/watch") {
                self.contextMenuDelegate?.ytWebViewSummarizeVideo(url: pageUrl)
            }
        }
    }
}
