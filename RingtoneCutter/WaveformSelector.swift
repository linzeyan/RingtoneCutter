import SwiftUI

/// Two tiers, because a 30-second clip is a sliver of a whole song: the overview
/// strip picks *where* in the song, the zoomed detail picks the exact edges.
struct WaveformSelector: View {
    let levels: [Float]
    @Binding var selection: TrimSelection
    let playhead: Double?

    /// Seconds of song the detail view shows: the longest clip plus room either side.
    static let detailSpan = TrimSelection.maxLength * 2

    @State private var viewportStart: Double = 0
    @State private var dragOrigin: TrimSelection?

    private var span: Double { min(Self.detailSpan, selection.duration) }
    private var needsOverview: Bool { selection.duration > Self.detailSpan }

    var body: some View {
        VStack(spacing: 12) {
            if needsOverview {
                overview
            }
            detail
            HStack {
                Text(TimeText.string(viewportStart))
                Spacer()
                Text(TimeText.string(viewportStart + span))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.tertiary)
            .padding(.horizontal, inset)
            .accessibilityHidden(true)
        }
        .overlay {
            if levels.isEmpty { ProgressView() }
        }
        .onAppear { recenter() }
        // Re-centering mid-drag would move the waveform under the finger.
        .onChange(of: selection) { if dragOrigin == nil { recenter() } }
    }

    private func recenter() {
        let middle = (selection.start + selection.end) / 2
        viewportStart = min(max(middle - span / 2, 0), max(selection.duration - span, 0))
    }

    // MARK: - Overview

    private var overview: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let duration = max(selection.duration, 0.001)
            let x = { (t: Double) in CGFloat(t / duration) * width }
            ZStack(alignment: .topLeading) {
                WaveformBars(levels: levels, range: 0...duration, selection: selection,
                             barSpacing: 3, minBarHeight: 2)
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    .frame(width: max(x(selection.end) - x(selection.start), 6), height: geo.size.height)
                    .offset(x: x(selection.start))
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            // Scrubbing: the window follows the finger, centered on it.
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let t = Double(value.location.x / width) * duration
                selection.shift(to: t - selection.length / 2)
            })
        }
        .frame(height: 36)
        .accessibilityIdentifier("overview")
        .padding(.horizontal, inset)
        .accessibilityElement()
        .accessibilityLabel("片段位置")
        .accessibilityValue("\(TimeText.string(selection.start)) 到 \(TimeText.string(selection.end))")
        .accessibilityAdjustableAction { direction in
            selection.shift(to: selection.start + (direction == .increment ? 5 : -5))
        }
    }

    // MARK: - Detail

    /// Handles sit outside the window so a short window stays draggable as a whole;
    /// the inset leaves them room at the very start and end of the song.
    private let inset: CGFloat = 20
    private let handleHitWidth: CGFloat = 28
    private let handleWidth: CGFloat = 12

    private var detail: some View {
        GeometryReader { geo in
            let width = max(geo.size.width - inset * 2, 1)
            let height = geo.size.height
            let span = max(self.span, 0.001)
            let x = { (t: Double) in inset + CGFloat((t - viewportStart) / span) * width }
            let seconds = { (dx: CGFloat) in Double(dx / width) * span }
            let xs = x(selection.start)
            let xe = x(selection.end)

            ZStack(alignment: .topLeading) {
                WaveformBars(levels: levels, range: viewportStart...(viewportStart + span), selection: selection,
                             barSpacing: 4, minBarHeight: 3)
                    .padding(.horizontal, inset)
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { tap in
                        let t = viewportStart + seconds(tap.location.x - inset)
                        selection.shift(to: t - selection.length / 2)
                    })

                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: 2)
                    }
                    .frame(width: max(xe - xs, 2), height: height)
                    .offset(x: xs)
                    .gesture(drag(seconds) { $0.shift(to: $0.start + $1) })
                    .accessibilityHidden(true)

                handle(edge: .leading, label: String(localized: "開始"), value: selection.start) { selection.setStart($0) }
                    .offset(x: xs - handleHitWidth)
                    .gesture(drag(seconds) { $0.setStart($0.start + $1) })

                handle(edge: .trailing, label: String(localized: "結束"), value: selection.end) { selection.setEnd($0) }
                    .offset(x: xe)
                    .gesture(drag(seconds) { $0.setEnd($0.end + $1) })

                if let playhead {
                    Capsule()
                        .fill(.primary)
                        .frame(width: 2, height: height + 8)
                        .offset(x: x(playhead) - 1, y: -4)
                        .allowsHitTesting(false)
                }
            }
            .clipShape(Rectangle().inset(by: -8))
        }
        .frame(minHeight: 96, maxHeight: 180)
    }

    private func handle(edge: HorizontalEdge, label: String, value: Double,
                        set: @escaping (Double) -> Void) -> some View {
        ZStack(alignment: edge == .leading ? .trailing : .leading) {
            Color.clear
            UnevenRoundedRectangle(
                topLeadingRadius: edge == .leading ? 6 : 0, bottomLeadingRadius: edge == .leading ? 6 : 0,
                bottomTrailingRadius: edge == .trailing ? 6 : 0, topTrailingRadius: edge == .trailing ? 6 : 0
            )
            .fill(Color.accentColor)
            .frame(width: handleWidth)
            .overlay {
                Capsule().fill(.black.opacity(0.55)).frame(width: 2, height: 20)
            }
        }
        .frame(width: handleHitWidth)
        .contentShape(Rectangle())
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(TimeText.string(value))
        .accessibilityAdjustableAction { direction in
            set(value + (direction == .increment ? 1 : -1))
        }
    }

    private func drag(_ seconds: @escaping (CGFloat) -> Double,
                      apply: @escaping (inout TrimSelection, Double) -> Void) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let origin = dragOrigin ?? selection
                dragOrigin = origin
                var updated = origin
                apply(&updated, seconds(value.translation.width))
                selection = updated
            }
            .onEnded { _ in
                dragOrigin = nil
                withAnimation(.snappy) { recenter() }
            }
    }
}

/// Bars for one stretch of the song; bars inside the selection are tinted.
private struct WaveformBars: View {
    let levels: [Float]
    let range: ClosedRange<Double>
    let selection: TrimSelection
    let barSpacing: CGFloat
    let minBarHeight: CGFloat

    var body: some View {
        Canvas { context, size in
            guard selection.duration > 0 else { return }
            let count = max(1, Int(size.width / barSpacing))
            let barWidth = size.width / CGFloat(count)
            let step = (range.upperBound - range.lowerBound) / Double(count)
            for i in 0..<count {
                let from = range.lowerBound + Double(i) * step
                let level = level(from: from, to: from + step)
                let barHeight = max(minBarHeight, CGFloat(level) * size.height)
                let rect = CGRect(x: CGFloat(i) * barWidth, y: (size.height - barHeight) / 2,
                                  width: max(barWidth - 1.5, 1), height: barHeight)
                let middle = from + step / 2
                let selected = middle >= selection.start && middle <= selection.end
                context.fill(Path(roundedRect: rect, cornerRadius: 1),
                             with: .color(selected ? Color.accentColor : Color.secondary.opacity(0.35)))
            }
        }
    }

    /// Levels are computed once at a fixed resolution; bars follow the zoom and width.
    private func level(from: Double, to: Double) -> Float {
        guard !levels.isEmpty else { return 0 }
        let scale = Double(levels.count) / selection.duration
        let lower = min(levels.count - 1, max(0, Int(from * scale)))
        let upper = max(lower + 1, min(levels.count, Int(to * scale)))
        return levels[lower..<upper].max() ?? 0
    }
}

enum TimeText {
    static func string(_ seconds: Double) -> String {
        // Round to the displayed tenth first: 179.98 s is 3:00.0, not 2:60.0.
        let tenths = Int((max(0, seconds) * 10).rounded())
        return String(format: "%d:%02d.%d", tenths / 600, tenths % 600 / 10, tenths % 10)
    }
}
