import AVFoundation
import Testing
@testable import RingtoneCutter

struct TrimSelectionTests {
    // A clip over 30s is silently rejected by iOS as a ringtone, so no
    // sequence of edits may ever produce one.
    @Test func neverExceedsRingtoneCap() {
        var s = TrimSelection(duration: 240)
        #expect(s.length == 30)

        s.setEnd(200)
        #expect(s.end == 200)
        #expect(s.length == 30)

        s.setStart(10)
        #expect(s.start == 10)
        #expect(s.length == 30)
    }

    @Test func shortSongUsesWholeSong() {
        let s = TrimSelection(duration: 12)
        #expect(s.start == 0 && s.end == 12)
    }

    @Test func edgesCannotCross() {
        var s = TrimSelection(duration: 100)
        s.setStart(50)
        s.setEnd(20)
        #expect(s.start <= s.end)
        #expect(s.end == 20)
    }

    // Dragging the window must keep the length the user already tuned,
    // even when it runs into either end of the song.
    @Test func slidingKeepsLengthAndStaysInSong() {
        var s = TrimSelection(duration: 100)
        s.setEnd(20)
        s.shift(to: 95)
        #expect(s.end == 100)
        #expect(s.length == 20)
        s.shift(to: -5)
        #expect(s.start == 0)
        #expect(s.length == 20)
    }
}

struct CloudLinkTests {
    // A share link opens a preview page; downloading it as-is yields HTML, not
    // audio. Each service must be rewritten to the address of the file itself.

    @Test func googleDriveShareLinkBecomesDirectDownload() {
        let share = URL(string: "https://drive.google.com/file/d/1AbC_dEf-123/view?usp=sharing")!
        #expect(CloudLink.downloadURL(for: share).absoluteString
            == "https://drive.usercontent.google.com/download?id=1AbC_dEf-123&export=download&confirm=t")
        let open = URL(string: "https://drive.google.com/open?id=1AbC_dEf-123")!
        #expect(CloudLink.downloadURL(for: open).absoluteString.contains("id=1AbC_dEf-123"))
    }

    @Test func dropboxKeepsItsKeyAndAsksForTheFile() {
        let share = URL(string: "https://www.dropbox.com/scl/fi/abc123/song.mp3?rlkey=xyz&dl=0")!
        let direct = CloudLink.downloadURL(for: share).absoluteString
        #expect(direct == "https://www.dropbox.com/scl/fi/abc123/song.mp3?rlkey=xyz&dl=1")
    }

    // Example share link and encoding from Microsoft's "Accessing shared items" docs.
    @Test func oneDriveUsesTheSharesAPI() {
        let share = URL(string: "https://onedrive.live.com/redir?resid=1231244193912!12&authKey=1201919!12921!1")!
        #expect(CloudLink.downloadURL(for: share).absoluteString
            == "https://api.onedrive.com/v1.0/shares/u!aHR0cHM6Ly9vbmVkcml2ZS5saXZlLmNvbS9yZWRpcj9yZXNpZD0xMjMxMjQ0MTkzOTEyITEyJmF1dGhLZXk9MTIwMTkxOSExMjkyMSEx/root/content")
    }

    @Test func sharePointAsksForDownload() {
        let share = URL(string: "https://contoso.sharepoint.com/:u:/g/personal/a_contoso_com/EabcD?e=XyZ")!
        #expect(CloudLink.downloadURL(for: share).absoluteString
            == "https://contoso.sharepoint.com/:u:/g/personal/a_contoso_com/EabcD?e=XyZ&download=1")
    }

    // S3 presigned URLs carry a signature in the query; touching it breaks the link.
    @Test func directLinksAreLeftAlone() {
        let s3 = URL(string: "https://bucket.s3.amazonaws.com/song.m4a?X-Amz-Signature=abc&X-Amz-Expires=600")!
        #expect(CloudLink.downloadURL(for: s3) == s3)
    }

    // Share sheets paste "Title\nhttps://…" or a whole message, not a bare URL.
    @Test func findsTheLinkInsidePastedText() {
        let pasted = "看看這首 👉 https://www.dropbox.com/s/abc/song.mp3?dl=0 好聽"
        #expect(CloudLink.url(in: pasted)?.host() == "www.dropbox.com")
        #expect(CloudLink.url(in: "http://example.com/a.mp3") == nil)
        #expect(CloudLink.url(in: "沒有網址") == nil)
    }
}

struct TimeTextTests {
    // Song lengths rarely land on a whole tenth; a value just under a minute
    // boundary once rendered as "2:60.0" on the editor header.
    @Test func roundsAcrossMinuteBoundary() {
        #expect(TimeText.string(179.98) == "3:00.0")
        #expect(TimeText.string(59.94) == "0:59.9")
        #expect(TimeText.string(61.6) == "1:01.6")
        #expect(TimeText.string(0) == "0:00.0")
    }
}

struct AudioTrimmerTests {
    // The exported file is what becomes the ringtone; its length must match
    // the window the user picked, not the source.
    @Test func exportedClipMatchesSelection() async throws {
        let dir = try temporaryDirectory()
        let source = dir.appendingPathComponent("tone.caf")
        try writeTone(to: source, seconds: 60)

        let output = dir.appendingPathComponent("clip.m4a")
        try await AudioTrimmer.trim(source, from: 10, to: 25, fades: false, output: output)

        let duration = try await AVURLAsset(url: output).load(.duration).seconds
        #expect(abs(duration - 15) < 0.1)
    }

    // A ringtone that starts at full volume mid-phrase is jarring; with fades on,
    // the opening must be much quieter than the body of the clip.
    @Test func fadesSoftenTheOpening() async throws {
        let dir = try temporaryDirectory()
        let source = dir.appendingPathComponent("tone.caf")
        try writeTone(to: source, seconds: 30)

        let faded = dir.appendingPathComponent("faded.m4a")
        try await AudioTrimmer.trim(source, from: 5, to: 20, fades: true, output: faded)
        let plain = dir.appendingPathComponent("plain.m4a")
        try await AudioTrimmer.trim(source, from: 5, to: 20, fades: false, output: plain)

        let fadedOpening = try rms(of: faded, from: 0.05, to: 0.15)
        let fadedBody = try rms(of: faded, from: 7, to: 8)
        let plainOpening = try rms(of: plain, from: 0.05, to: 0.15)
        #expect(fadedOpening < fadedBody * 0.4)
        #expect(plainOpening > fadedBody * 0.8)
    }
}

struct WaveformTests {
    // The waveform is how the user finds the part worth cutting, so loud and
    // silent stretches of the song must show up where they are.
    @Test func levelsFollowWhereTheSoundIs() async throws {
        let dir = try temporaryDirectory()
        let source = dir.appendingPathComponent("half.caf")
        try writeTone(to: source, seconds: 40, silentAfter: 20)

        let levels = try await Waveform.levels(of: source, bins: 40)
        #expect(levels.count == 40)
        #expect(levels[2..<18].allSatisfy { $0 > 0.8 })
        #expect(levels[22..<38].allSatisfy { $0 < 0.05 })
    }

    // A long video takes a while to read, so the waveform fills in from the start;
    // what is not read yet must stay blank, never drawn as if it were silence.
    @Test func partialLevelsOnlyLeaveTheUnreadEndBlank() async throws {
        let dir = try temporaryDirectory()
        let source = dir.appendingPathComponent("half.caf")
        try writeTone(to: source, seconds: 40, silentAfter: 20)

        let seen = await MainActor.run { Partials() }
        let levels = try await Waveform.levels(of: source, bins: 40) { seen.all.append($0) }
        let partials = await seen.all
        #expect(partials.contains { $0.contains { $0.isNaN } })
        for partial in partials {
            let read = partial.prefix { !$0.isNaN }
            #expect(partial.dropFirst(read.count).allSatisfy { $0.isNaN })
        }
        #expect(!levels.contains { $0.isNaN })
    }
}

@MainActor
private final class Partials {
    var all: [[Float]] = []
}

private func temporaryDirectory() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func writeTone(to url: URL, seconds: Double, silentAfter: Double? = nil) throws {
    let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    let frames = AVAudioFrameCount(seconds * format.sampleRate)
    let silentFrom = Int((silentAfter ?? seconds) * format.sampleRate)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    buffer.frameLength = frames
    let samples = buffer.floatChannelData![0]
    for i in 0..<Int(frames) {
        samples[i] = i < silentFrom ? sin(2 * .pi * 440 * Float(i) / Float(format.sampleRate)) * 0.3 : 0
    }
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try file.write(from: buffer)
}

private func rms(of url: URL, from start: Double, to end: Double) throws -> Float {
    let file = try AVAudioFile(forReading: url)
    let rate = file.processingFormat.sampleRate
    file.framePosition = AVAudioFramePosition(start * rate)
    let count = AVAudioFrameCount((end - start) * rate)
    let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: count)!
    try file.read(into: buffer, frameCount: count)
    let samples = buffer.floatChannelData![0]
    let n = Int(buffer.frameLength)
    let sum = (0..<n).reduce(Float(0)) { $0 + samples[$1] * samples[$1] }
    return (sum / Float(max(n, 1))).squareRoot()
}
