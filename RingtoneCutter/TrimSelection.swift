import Foundation

/// The clip window the user picks. Invariant: 0 <= start <= end <= duration
/// and end - start <= maxLength.
struct TrimSelection: Equatable {
    /// iOS only offers "Use as Ringtone" for audio of 30 seconds or less.
    static let maxLength: Double = 30

    let duration: Double
    private(set) var start: Double
    private(set) var end: Double

    init(duration: Double) {
        self.duration = max(0, duration)
        start = 0
        end = min(self.duration, Self.maxLength)
    }

    var length: Double { end - start }

    /// Moving one edge drags the other along instead of refusing the move:
    /// the user is choosing where that edge goes, the cap is our problem.
    mutating func setStart(_ value: Double) {
        start = min(max(value, 0), duration)
        end = min(max(end, start), start + Self.maxLength)
    }

    mutating func setEnd(_ value: Double) {
        end = min(max(value, 0), duration)
        start = max(min(start, end), end - Self.maxLength)
    }

    /// Slides the whole window, keeping its length, stopping at either end of the song.
    mutating func shift(to newStart: Double) {
        let length = self.length
        start = min(max(newStart, 0), duration - length)
        end = start + length
    }
}
