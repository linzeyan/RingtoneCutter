import AVFoundation
import Observation

@MainActor
@Observable
final class EditorModel {
    private(set) var sourceURL: URL?
    private(set) var sourceName = ""
    private(set) var levels: [Float] = []
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
        do {
            let local = try copyToTemporary(picked)
            let asset = AVURLAsset(url: local)
            let (duration, playable) = try await asset.load(.duration, .isPlayable)
            let track = try await asset.loadTracks(withMediaType: .audio).first
            guard playable, let track, duration.seconds > 0 else {
                throw AudioTrimmer.TrimError.unsupportedSource
            }

            pickedURL = picked.standardizedFileURL
            sourceURL = local
            sourceName = name
            self.track = track
            ringtoneName = picked.deletingPathExtension().lastPathComponent
            selection = TrimSelection(duration: duration.seconds)
            exportedURL = nil
            loadWaveform(local)
        } catch {
            errorMessage = String(localized: "無法讀取「\(name)」。WMA、WebM、MKV 等格式請先轉成 MP3 或 M4A。")
                + "\n\n" + SupportedFormats.summary
        }
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
        waveformTask = Task {
            let levels = (try? await Waveform.levels(of: url, bins: 2_000)) ?? []
            if !Task.isCancelled { self.levels = levels }
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

    func export() async -> URL? {
        guard let sourceURL else { return nil }
        stopPreview()
        isExporting = true
        defer { isExporting = false }
        var output = URL.documentsDirectory.appendingPathComponent(fileName).appendingPathExtension("m4a")
        // A song picked from this app's own folder must not be overwritten by its clip.
        if output.standardizedFileURL == pickedURL {
            output = URL.documentsDirectory.appendingPathComponent(String(localized: "\(fileName) 鈴聲")).appendingPathExtension("m4a")
        }
        do {
            try await AudioTrimmer.trim(sourceURL, from: selection.start, to: selection.end, fades: fades, output: output)
            exportedURL = output
            exportCount += 1
            return output
        } catch {
            errorMessage = String(localized: "剪輯失敗：\(error.localizedDescription)")
            return nil
        }
    }

    private var fileName: String {
        let cleaned = ringtoneName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? String(localized: "鈴聲") : cleaned
    }
}
