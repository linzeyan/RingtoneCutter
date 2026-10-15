import AVFoundation

enum AudioTrimmer {
    enum TrimError: LocalizedError {
        case unsupportedSource

        var errorDescription: String? { String(localized: "這個音檔格式無法轉換") }
    }

    static let fadeIn: Double = 0.5
    static let fadeOut: Double = 1.5

    /// Volume ramps in source time. Shared by preview and export so what the user
    /// hears while trimming is exactly what ends up in the ringtone.
    static func fadeMix(for track: AVAssetTrack, from start: Double, to end: Double) -> AVAudioMix {
        // Short clips keep at least a third of their length at full volume.
        let fadeIn = min(Self.fadeIn, (end - start) / 3)
        let fadeOut = min(Self.fadeOut, (end - start) / 3)
        let parameters = AVMutableAudioMixInputParameters(track: track)
        parameters.setVolumeRamp(fromStartVolume: 0, toEndVolume: 1,
                                 timeRange: CMTimeRange(start: time(start), duration: time(fadeIn)))
        parameters.setVolumeRamp(fromStartVolume: 1, toEndVolume: 0,
                                 timeRange: CMTimeRange(start: time(end - fadeOut), duration: time(fadeOut)))
        let mix = AVMutableAudioMix()
        mix.inputParameters = [parameters]
        return mix
    }

    /// Re-encodes [start, end) of `source` as AAC in an .m4a container,
    /// the format the system ringtone picker accepts.
    static func trim(_ source: URL, from start: Double, to end: Double, fades: Bool, output: URL) async throws {
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first,
              let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A)
        else {
            throw TrimError.unsupportedSource
        }
        session.timeRange = CMTimeRange(start: time(start), end: time(end))
        if fades {
            session.audioMix = fadeMix(for: track, from: start, to: end)
        }
        // The exporter refuses to overwrite; re-exporting the same song must replace the old clip.
        try? FileManager.default.removeItem(at: output)
        try await session.export(to: output, as: .m4a)
    }

    static func time(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 600)
    }
}
