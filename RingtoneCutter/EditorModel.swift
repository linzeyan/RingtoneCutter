import AVFoundation
import Observation
import PhotosUI
import SwiftUI

@MainActor
@Observable
final class EditorModel {
    private(set) var sourceURL: URL?
    private(set) var sourceName = ""
    /// Fills in from the start while a long file is read; NaN marks bins not read yet.
    private(set) var levels: [Float] = []
    private(set) var isReadingWaveform = false
    private(set) var isLoading = false
    var selection = TrimSelection(duration: 0) {
        didSet { if selection != oldValue { invalidateClip() } }
    }
    var fades = true {
        didSet { if fades != oldValue { invalidateClip() } }
    }
    /// Becomes the file name, which is what the system ringtone list shows.
    var ringtoneName = "" {
        didSet { if ringtoneName != oldValue { exportedURL = nil } }
    }
    private(set) var exportedURL: URL?
    /// Bumped per successful export; drives the success haptic.
    private(set) var exportCount = 0
    private(set) var isExporting = false
    private(set) var playhead: Double?
    var errorMessage: String?

    private var pickedURL: URL?
    private var track: AVAssetTrack?
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var waveformTask: Task<Void, Never>?

    var isPlaying: Bool { player != nil }

    func load(_ picked: URL) async {
        stopPreview()
        isLoading = true
        defer { isLoading = false }
        let name = picked.lastPathComponent
        var local: URL?
        do {
            let copy = try copyToTemporary(picked)
            local = copy
            let asset = AVURLAsset(url: copy)
            let (duration, playable) = try await asset.load(.duration, .isPlayable)
            let track = try await asset.loadTracks(withMediaType: .audio).first
            guard playable, let track, duration.seconds > 0 else {
                throw AudioTrimmer.TrimError.unsupportedSource
            }

            // One source copy at a time: a video can be several GB, and tmp is
            // only purged when the system runs short.
            if let previous = sourceURL, previous != copy {
                try? FileManager.default.removeItem(at: previous)
            }
            pickedURL = picked.standardizedFileURL
            sourceURL = copy
            sourceName = name
            self.track = track
            ringtoneName = picked.deletingPathExtension().lastPathComponent
            selection = TrimSelection(duration: duration.seconds)
            exportedURL = nil
            loadWaveform(copy)
        } catch {
            if let local, local != sourceURL { try? FileManager.default.removeItem(at: local) }
            errorMessage = String(localized: "無法讀取「\(name)」。WMA、WebM、MKV 等格式請先轉成 MP3 或 M4A。")
                + "\n\n" + SupportedFormats.summary
        }
    }

    /// A video from Photos may first have to come down from iCloud, which can take a
    /// while, so the loading state covers the transfer as well as the decode.
    func loadVideo(_ item: PhotosPickerItem) async {
        stopPreview()
        isLoading = true
        let video = try? await item.loadTransferable(type: PickedVideo.self)
        isLoading = false
        guard let video else {
            errorMessage = String(localized: "無法讀取這支影片")
            return
        }
        await load(video.url)
        // `load` keeps its own copy; this one would be a second multi-GB file.
        try? FileManager.default.removeItem(at: video.url.deletingLastPathComponent())
    }

    // MARK: - Links

    private(set) var isDownloading = false
    /// Fraction downloaded, or nil while the server has not said how big the file is.
    private(set) var downloadProgress: Double?
    private var downloadTask: Task<Void, Never>?

    func loadLink(_ text: String) {
        guard let link = CloudLink.url(in: text) else {
            errorMessage = String(localized: "找不到 https 開頭的網址。")
            return
        }
        stopPreview()
        downloadTask?.cancel()
        isDownloading = true
        downloadProgress = nil
        downloadTask = Task {
            let downloader = LinkDownloader { [weak self] fraction in
                Task { @MainActor in self?.downloadProgress = fraction }
            }
            do {
                let file = try await downloader.download(CloudLink.downloadURL(for: link))
                isDownloading = false
                await load(file)
                try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
            } catch {
                isDownloading = false
                if !Self.isCancellation(error) {
                    errorMessage = String(localized: "下載失敗：\(error.localizedDescription)")
                }
            }
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    /// The security scope of a picked file ends when `load` returns, but preview
    /// and export need it later, so the editor works from a private copy.
    private func copyToTemporary(_ picked: URL) throws -> URL {
        let accessing = picked.startAccessingSecurityScopedResource()
        defer { if accessing { picked.stopAccessingSecurityScopedResource() } }
        let local = FileManager.default.temporaryDirectory.appendingPathComponent(picked.lastPathComponent)
        if local.standardizedFileURL != picked.standardizedFileURL {
            try? FileManager.default.removeItem(at: local)
            try FileManager.default.copyItem(at: picked, to: local)
        }
        return local
    }

    private func loadWaveform(_ url: URL) {
        waveformTask?.cancel()
        levels = []
        isReadingWaveform = true
        waveformTask = Task {
            let levels = (try? await Waveform.levels(of: url, bins: 2_000) { partial in
                // Runs inside this task, so a superseded file stops drawing at once.
                if !Task.isCancelled { self.levels = partial }
            }) ?? []
            if !Task.isCancelled {
                self.levels = levels
                isReadingWaveform = false
            }
        }
    }

    private func invalidateClip() {
        exportedURL = nil
        stopPreview()
    }

    // MARK: - Preview

    func togglePreview() {
        isPlaying ? stopPreview() : startPreview()
    }

    private func startPreview() {
        guard let sourceURL, let track else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        let item = AVPlayerItem(url: sourceURL)
        if fades {
            item.audioMix = AudioTrimmer.fadeMix(for: track, from: selection.start, to: selection.end)
        }
        item.forwardPlaybackEndTime = AudioTrimmer.time(selection.end)
        let player = AVPlayer(playerItem: item)
        self.player = player
        playhead = selection.start

        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.playhead = time.seconds }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopPreview() }
        }

        let start = AudioTrimmer.time(selection.start)
        Task {
            await player.seek(to: start, toleranceBefore: .zero, toleranceAfter: .zero)
            // Stopped (or restarted) while seeking.
            guard self.player === player else { return }
            player.play()
        }
    }

    func stopPreview() {
        guard let player else { return }
        player.pause()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = nil
        endObserver = nil
        self.player = nil
        playhead = nil
    }

    // MARK: - Export

    /// UserDefaults key of the iPhone/iCloud save-location switch in the toolbar.
    static let iCloudKey = "saveToICloud"
    /// Where the last export went; false with the switch on means iCloud was unavailable.
    private(set) var savedToICloud = false

    func export() async -> URL? {
        guard let sourceURL else { return nil }
        stopPreview()
        isExporting = true
        defer { isExporting = false }
        let iCloudFolder = UserDefaults.standard.bool(forKey: Self.iCloudKey) ? await Self.iCloudDocuments() : nil
        let folder = iCloudFolder ?? URL.documentsDirectory
        var output = folder.appendingPathComponent(fileName).appendingPathExtension("m4a")
        // A song picked from this app's own folder must not be overwritten by its clip.
        if output.standardizedFileURL == pickedURL {
            output = folder.appendingPathComponent(String(localized: "\(fileName) 鈴聲")).appendingPathExtension("m4a")
        }
        do {
            if iCloudFolder != nil {
                // Exported outside the container, then handed over whole: writing in
                // place would let iCloud start uploading a half-written file. Its own
                // folder, so a clip named like the source cannot replace the source copy.
                let staging = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                let local = staging.appendingPathComponent(output.lastPathComponent)
                try await AudioTrimmer.trim(sourceURL, from: selection.start, to: selection.end, fades: fades, output: local)
                try await Self.moveToICloud(local, to: output)
                try? FileManager.default.removeItem(at: staging)
            } else {
                try await AudioTrimmer.trim(sourceURL, from: selection.start, to: selection.end, fades: fades, output: output)
            }
            savedToICloud = iCloudFolder != nil
            exportedURL = output
            exportCount += 1
            return output
        } catch {
            errorMessage = String(localized: "剪輯失敗：\(error.localizedDescription)")
            return nil
        }
    }

    /// Nil when not signed in to iCloud or iCloud Drive is off for this app.
    nonisolated private static func iCloudDocuments() async -> URL? {
        // Blocks while iCloud sets the container up on first use: never on the main thread.
        await Task.detached {
            guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else { return nil }
            // Only Documents is shown in Files and Finder.
            let documents = container.appendingPathComponent("Documents", isDirectory: true)
            try? FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
            return documents
        }.value
    }

    nonisolated private static func moveToICloud(_ local: URL, to destination: URL) async throws {
        try await Task.detached {
            // Re-making a ringtone replaces it, as it does locally; setUbiquitous
            // refuses an existing destination. Coordinated so a sync in flight
            // sees the delete instead of resurrecting the old file.
            NSFileCoordinator().coordinate(writingItemAt: destination, options: .forDeleting, error: nil) { url in
                try? FileManager.default.removeItem(at: url)
            }
            try FileManager.default.setUbiquitous(true, itemAt: local, destinationURL: destination)
        }.value
    }

    private var fileName: String {
        let cleaned = ringtoneName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? String(localized: "鈴聲") : cleaned
    }
}
