import Foundation
import MediaPlayer
import WebKit

class MediaKeyHandler {
    static let shared = MediaKeyHandler()
    private var nowPlayingInfo: [String: Any] = [:]

    func setup() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.executeJS("document.querySelector('video')?.play()")
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.executeJS("document.querySelector('video')?.pause()")
            return .success
        }

        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.executeJS("""
                (function() {
                    const v = document.querySelector('video');
                    if (v) { v.paused ? v.play() : v.pause(); }
                })()
            """)
            return .success
        }

        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.executeJS("document.querySelector('.ytp-next-button')?.click()")
            return .success
        }

        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.addTarget { _ in
            return .success
        }

        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let posEvent = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.executeJS("document.querySelector('video').currentTime = \(posEvent.positionTime)")
            return .success
        }
    }

    func updateNowPlaying(title: String, channel: String, duration: Double, currentTime: Double, paused: Bool) {
        nowPlayingInfo[MPMediaItemPropertyTitle] = title
        nowPlayingInfo[MPMediaItemPropertyArtist] = channel
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = paused ? 0.0 : 1.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        MPNowPlayingInfoCenter.default().playbackState = paused ? .paused : .playing
    }

    func clearNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    private var activeWebView: WKWebView? {
        guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else { return nil }
        return appDelegate.mainWindowController?.tabManager.activeTab?.webView
    }

    private func executeJS(_ js: String) {
        DispatchQueue.main.async {
            self.activeWebView?.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}
