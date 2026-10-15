import AVFoundation

enum Waveform {
    enum WaveformError: Error {
        case noAudio
    }

    /// Loudness (RMS) per bin across the whole song, normalized so the loudest bin is 1.
    /// RMS rather than peak: mastered pop music hits full scale almost everywhere,
    /// so peaks draw a flat block, while RMS shows verses, choruses and breaks.
    static func levels(of url: URL, bins: Int) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw WaveformError.noAudio
        }
        let duration = try await asset.load(.duration).seconds

        // A bar on screen covers a fraction of a second at best, so decode mono at the
        // lowest rate the reader accepts: a six-minute song is ~3M samples, not ~32M.
        let sampleRate = 8_000.0
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: sampleRate,
        ])
        reader.add(output)
        reader.startReading()

        let total = max(1, Int(duration * sampleRate))
        var sums = [Float](repeating: 0, count: bins)
        var counts = [Int](repeating: 0, count: bins)
        var index = 0
        while let buffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var samples = [Int16](repeating: 0, count: length / 2)
            samples.withUnsafeMutableBytes { raw in
                _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: raw.baseAddress!)
            }
            for sample in samples {
                let bin = min(bins - 1, index * bins / total)
                let value = Float(sample) / 32_768
                sums[bin] += value * value
                counts[bin] += 1
                index += 1
            }
        }
        if reader.status == .failed, let error = reader.error {
            throw error
        }
        let levels = zip(sums, counts).map { $1 > 0 ? ($0 / Float($1)).squareRoot() : 0 }
        let loudest = levels.max() ?? 0
        return loudest > 0 ? levels.map { $0 / loudest } : levels
    }
}
