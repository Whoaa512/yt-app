import Foundation
import SQLite3

struct DownloadedVideo: Identifiable {
    var id: String
    var title: String
    var channel: String
    var duration: Int
    var description: String
    var uploadDate: String
    var viewCount: Int64
    var thumbnailPath: String
    var videoPath: String
    var fileSize: Int64
    var downloadedAt: Date
    var sourceURL: String
    var isExternal: Bool

    var durationFormatted: String {
        let h = duration / 3600
        let m = (duration % 3600) / 60
        let s = duration % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    var fileSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

struct ActiveDownload {
    var id: String
    var title: String
    var progress: Double
    var status: DownloadStatus
}

enum DownloadStatus {
    case queued
    case downloading
    case processing
    case completed
    case failed(String)
}

protocol DownloadManagerDelegate: AnyObject {
    func downloadManager(_ manager: DownloadManager, didUpdateProgress download: ActiveDownload)
    func downloadManager(_ manager: DownloadManager, didComplete videoId: String)
    func downloadManager(_ manager: DownloadManager, didFail videoId: String, error: String)
}

class DownloadManager {
    static let shared = DownloadManager()
    weak var delegate: DownloadManagerDelegate?

    private var db: OpaquePointer?
    private var activeDownloads: [String: ActiveDownload] = [:]
    private var downloadQueue: [(url: String, quality: String?)] = []
    private var currentProcess: Process?
    private var isDownloading = false
    private let serialQueue = DispatchQueue(label: "com.ytapp.downloads")

    var activeDownloadsList: [ActiveDownload] {
        Array(activeDownloads.values)
    }

    var hasActiveDownloads: Bool {
        !activeDownloads.isEmpty
    }

    var overallProgress: Double {
        guard !activeDownloads.isEmpty else { return 0 }
        let total = activeDownloads.values.reduce(0.0) { $0 + $1.progress }
        return total / Double(activeDownloads.count)
    }

    func setup() {
        let dir = Settings.downloadPath
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(atPath: dir + "/thumbnails", withIntermediateDirectories: true)

        let dbPath = dir + "/downloads.db"
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else { return }

        let sql = """
        CREATE TABLE IF NOT EXISTS downloads (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            channel TEXT DEFAULT '',
            duration INTEGER DEFAULT 0,
            description TEXT DEFAULT '',
            upload_date TEXT DEFAULT '',
            view_count INTEGER DEFAULT 0,
            thumbnail_path TEXT DEFAULT '',
            video_path TEXT NOT NULL,
            file_size INTEGER DEFAULT 0,
            downloaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            source_url TEXT DEFAULT ''
        );
        CREATE INDEX IF NOT EXISTS idx_downloads_title ON downloads(title);
        CREATE INDEX IF NOT EXISTS idx_downloads_date ON downloads(downloaded_at DESC);
        """
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    func download(url: String, quality: String? = nil) {
        serialQueue.async { [weak self] in
            self?.downloadQueue.append((url: url, quality: quality))
            self?.processNextDownload()
        }
    }

    private func processNextDownload() {
        guard !isDownloading, let next = downloadQueue.first else { return }
        downloadQueue.removeFirst()
        isDownloading = true

        let videoId = extractVideoId(from: next.url) ?? UUID().uuidString
        let download = ActiveDownload(id: videoId, title: "Fetching info...", progress: 0, status: .queued)
        activeDownloads[videoId] = download

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.downloadManager(self, didUpdateProgress: download)
        }

        runYTDLP(url: next.url, videoId: videoId, quality: next.quality ?? Settings.downloadQuality)
    }

    private func runYTDLP(url: String, videoId: String, quality: String) {
        let downloadDir = Settings.downloadPath
        let thumbDir = downloadDir + "/thumbnails"

        let ytdlpPath = findYTDLP()
        guard !ytdlpPath.isEmpty else {
            failDownload(videoId: videoId, error: "yt-dlp not found in PATH")
            return
        }

        let qualityFormat: String
        switch quality {
        case "4k": qualityFormat = "bestvideo[height<=2160]+bestaudio/best[height<=2160]"
        case "1080p": qualityFormat = "bestvideo[height<=1080]+bestaudio/best[height<=1080]"
        case "720p": qualityFormat = "bestvideo[height<=720]+bestaudio/best[height<=720]"
        case "480p": qualityFormat = "bestvideo[height<=480]+bestaudio/best[height<=480]"
        default: qualityFormat = "bestvideo[height<=1080]+bestaudio/best[height<=1080]"
        }

        var args = [
            "-f", qualityFormat,
            "--merge-output-format", "webm/mp4",
            "-o", downloadDir + "/%(id)s.%(ext)s",
            "--write-thumbnail",
            "--convert-thumbnails", "jpg",
            "-o", "thumbnail:\(thumbDir)/%(id)s.%(ext)s",
            "--write-info-json",
            "-o", "infojson:\(downloadDir)/%(id)s.%(ext)s",
            "--progress",
            "--newline",
            "--no-overwrites",
        ]

        if Settings.downloadSubtitles {
            args += ["--write-subs", "--embed-subs", "--sub-langs", "en.*"]
        }

        args.append(url)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytdlpPath)
        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
            self?.parseYTDLPOutput(line: line, videoId: videoId)
        }

        process.terminationHandler = { [weak self] proc in
            guard let self else { return }
            pipe.fileHandleForReading.readabilityHandler = nil

            if proc.terminationStatus == 0 {
                self.finalizeDownload(videoId: videoId, downloadDir: downloadDir)
            } else {
                self.failDownload(videoId: videoId, error: "yt-dlp exited with code \(proc.terminationStatus)")
            }
        }

        currentProcess = process

        do {
            try process.run()
        } catch {
            failDownload(videoId: videoId, error: error.localizedDescription)
        }
    }

    private func parseYTDLPOutput(line: String, videoId: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.contains("[download]"), let pctRange = trimmed.range(of: #"(\d+\.?\d*)%"#, options: .regularExpression) {
            let pctStr = trimmed[pctRange].dropLast()
            if let pct = Double(pctStr) {
                updateProgress(videoId: videoId, progress: pct / 100.0, status: .downloading)
            }
        } else if trimmed.contains("[Merger]") || trimmed.contains("[ExtractAudio]") || trimmed.contains("[FixupM3u8]") {
            updateProgress(videoId: videoId, progress: 0.95, status: .processing)
        } else if trimmed.hasPrefix("[info]") || trimmed.hasPrefix("[youtube]") {
            if let titleRange = trimmed.range(of: #"Downloading .+ - (.+)"#, options: .regularExpression) {
                let title = String(trimmed[titleRange])
                activeDownloads[videoId]?.title = title
            }
        }
    }

    private func updateProgress(videoId: String, progress: Double, status: DownloadStatus) {
        serialQueue.async { [weak self] in
            guard let self, var dl = self.activeDownloads[videoId] else { return }
            dl.progress = progress
            dl.status = status
            self.activeDownloads[videoId] = dl

            DispatchQueue.main.async {
                self.delegate?.downloadManager(self, didUpdateProgress: dl)
            }
        }
    }

    private func finalizeDownload(videoId: String, downloadDir: String) {
        let fm = FileManager.default
        let thumbDir = downloadDir + "/thumbnails"

        var videoFile: String?
        var thumbFile: String?
        var infoFile: String?

        if let contents = try? fm.contentsOfDirectory(atPath: downloadDir) {
            for file in contents {
                if file.hasPrefix(videoId) {
                    if file.hasSuffix(".webm") || file.hasSuffix(".mp4") || file.hasSuffix(".mkv") {
                        videoFile = downloadDir + "/" + file
                    } else if file.hasSuffix(".info.json") {
                        infoFile = downloadDir + "/" + file
                    }
                }
            }
        }

        if let thumbContents = try? fm.contentsOfDirectory(atPath: thumbDir) {
            for file in thumbContents {
                if file.hasPrefix(videoId) && (file.hasSuffix(".jpg") || file.hasSuffix(".webp") || file.hasSuffix(".png")) {
                    thumbFile = thumbDir + "/" + file
                }
            }
        }

        guard let videoPath = videoFile else {
            failDownload(videoId: videoId, error: "Video file not found after download")
            return
        }

        var title = videoId
        var channel = ""
        var duration = 0
        var desc = ""
        var uploadDate = ""
        var viewCount: Int64 = 0

        if let jsonPath = infoFile,
           let data = fm.contents(atPath: jsonPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            title = json["title"] as? String ?? videoId
            channel = json["uploader"] as? String ?? json["channel"] as? String ?? ""
            duration = json["duration"] as? Int ?? 0
            desc = json["description"] as? String ?? ""
            uploadDate = json["upload_date"] as? String ?? ""
            viewCount = json["view_count"] as? Int64 ?? 0

            try? fm.removeItem(atPath: jsonPath)
        }

        let fileSize = (try? fm.attributesOfItem(atPath: videoPath)[.size] as? Int64) ?? 0

        saveToDatabase(DownloadedVideo(
            id: videoId, title: title, channel: channel, duration: duration,
            description: desc, uploadDate: uploadDate, viewCount: viewCount,
            thumbnailPath: thumbFile ?? "", videoPath: videoPath, fileSize: fileSize,
            downloadedAt: Date(), sourceURL: "", isExternal: false
        ))

        activeDownloads.removeValue(forKey: videoId)
        isDownloading = false

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.downloadManager(self, didComplete: videoId)
        }

        serialQueue.async { [weak self] in
            self?.processNextDownload()
        }
    }

    private func failDownload(videoId: String, error: String) {
        activeDownloads.removeValue(forKey: videoId)
        isDownloading = false

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.delegate?.downloadManager(self, didFail: videoId, error: error)
        }

        serialQueue.async { [weak self] in
            self?.processNextDownload()
        }
    }

    private func saveToDatabase(_ video: DownloadedVideo) {
        guard let db else { return }
        let sql = """
        INSERT OR REPLACE INTO downloads
        (id, title, channel, duration, description, upload_date, view_count, thumbnail_path, video_path, file_size, source_url)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(stmt, 1, (video.id as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (video.title as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (video.channel as NSString).utf8String, -1, nil)
        sqlite3_bind_int(stmt, 4, Int32(video.duration))
        sqlite3_bind_text(stmt, 5, (video.description as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 6, (video.uploadDate as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(stmt, 7, video.viewCount)
        sqlite3_bind_text(stmt, 8, (video.thumbnailPath as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 9, (video.videoPath as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(stmt, 10, video.fileSize)
        sqlite3_bind_text(stmt, 11, (video.sourceURL as NSString).utf8String, -1, nil)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }

    func allVideos(query: String = "") -> [DownloadedVideo] {
        var results = databaseVideos(query: query)
        results += scanExternalDirectories(query: query)
        return results
    }

    private func databaseVideos(query: String = "") -> [DownloadedVideo] {
        guard let db else { return [] }
        var results: [DownloadedVideo] = []

        let sql: String
        if query.isEmpty {
            sql = "SELECT id, title, channel, duration, description, upload_date, view_count, thumbnail_path, video_path, file_size, downloaded_at, source_url FROM downloads ORDER BY downloaded_at DESC"
        } else {
            sql = "SELECT id, title, channel, duration, description, upload_date, view_count, thumbnail_path, video_path, file_size, downloaded_at, source_url FROM downloads WHERE title LIKE ? OR channel LIKE ? ORDER BY downloaded_at DESC"
        }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }

        if !query.isEmpty {
            let pattern = "%\(query)%"
            sqlite3_bind_text(stmt, 1, (pattern as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (pattern as NSString).utf8String, -1, nil)
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(stmt, 0))
            let title = String(cString: sqlite3_column_text(stmt, 1))
            let channel = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
            let duration = Int(sqlite3_column_int(stmt, 3))
            let desc = sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? ""
            let uploadDate = sqlite3_column_text(stmt, 5).map { String(cString: $0) } ?? ""
            let viewCount = sqlite3_column_int64(stmt, 6)
            let thumbPath = sqlite3_column_text(stmt, 7).map { String(cString: $0) } ?? ""
            let videoPath = String(cString: sqlite3_column_text(stmt, 8))
            let fileSize = sqlite3_column_int64(stmt, 9)
            let dateStr = sqlite3_column_text(stmt, 10).map { String(cString: $0) }
            let downloadedAt = dateStr.flatMap { dateFormatter.date(from: $0) } ?? Date()
            let sourceURL = sqlite3_column_text(stmt, 11).map { String(cString: $0) } ?? ""

            let fm = FileManager.default
            guard fm.fileExists(atPath: videoPath) else { continue }

            results.append(DownloadedVideo(
                id: id, title: title, channel: channel, duration: duration,
                description: desc, uploadDate: uploadDate, viewCount: viewCount,
                thumbnailPath: thumbPath, videoPath: videoPath, fileSize: fileSize,
                downloadedAt: downloadedAt, sourceURL: sourceURL, isExternal: false
            ))
        }
        sqlite3_finalize(stmt)
        return results
    }

    func scanExternalDirectories(query: String = "") -> [DownloadedVideo] {
        var results: [DownloadedVideo] = []
        let fm = FileManager.default
        let extensions = ["mp4", "webm", "mkv"]
        let queryLower = query.lowercased()

        for dir in Settings.offlineExtraDirectories {
            guard let files = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for file in files.sorted() {
                let ext = (file as NSString).pathExtension.lowercased()
                guard extensions.contains(ext) else { continue }

                let title = (file as NSString).deletingPathExtension
                if !query.isEmpty && !title.lowercased().contains(queryLower) { continue }

                let fullPath = dir + "/" + file
                let fileSize = (try? fm.attributesOfItem(atPath: fullPath)[.size] as? Int64) ?? 0
                let modDate = (try? fm.attributesOfItem(atPath: fullPath)[.modificationDate] as? Date) ?? Date()

                results.append(DownloadedVideo(
                    id: "ext_" + fullPath.hash.description,
                    title: title, channel: "", duration: 0,
                    description: "", uploadDate: "", viewCount: 0,
                    thumbnailPath: "", videoPath: fullPath, fileSize: fileSize,
                    downloadedAt: modDate, sourceURL: "", isExternal: true
                ))
            }
        }
        return results
    }

    func deleteVideo(_ video: DownloadedVideo) {
        guard !video.isExternal else { return }
        let fm = FileManager.default
        try? fm.removeItem(atPath: video.videoPath)
        if !video.thumbnailPath.isEmpty { try? fm.removeItem(atPath: video.thumbnailPath) }

        guard let db else { return }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM downloads WHERE id = ?", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (video.id as NSString).utf8String, -1, nil)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    func cancelAllDownloads() {
        currentProcess?.terminate()
        activeDownloads.removeAll()
        downloadQueue.removeAll()
        isDownloading = false
    }

    private func extractVideoId(from url: String) -> String? {
        if let range = url.range(of: #"[?&]v=([a-zA-Z0-9_-]{11})"#, options: .regularExpression) {
            let match = url[range]
            return String(match.dropFirst(3))
        }
        if let range = url.range(of: #"youtu\.be/([a-zA-Z0-9_-]{11})"#, options: .regularExpression) {
            let match = url[range]
            return String(match.suffix(11))
        }
        if let range = url.range(of: #"/shorts/([a-zA-Z0-9_-]{11})"#, options: .regularExpression) {
            let match = url[range]
            return String(match.suffix(11))
        }
        return nil
    }

    private func findYTDLP() -> String {
        let knownPaths = [
            "/usr/local/bin/yt-dlp",
            "/opt/homebrew/bin/yt-dlp",
            NSString("~/.local/bin/yt-dlp").expandingTildeInPath,
            NSString("~/.local/share/mise/installs/yt-dlp/2026.02.21/yt-dlp").expandingTildeInPath,
        ]
        for path in knownPaths {
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }

        let whichProcess = Process()
        whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProcess.arguments = ["yt-dlp"]
        let whichPipe = Pipe()
        whichProcess.standardOutput = whichPipe
        try? whichProcess.run()
        whichProcess.waitUntilExit()
        let output = String(data: whichPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return output
    }
}
