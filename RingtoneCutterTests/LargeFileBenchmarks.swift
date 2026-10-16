import Darwin
import Foundation
import Testing
@testable import RingtoneCutter

/// Opt-in measurement of big inputs (a few minutes of 4K video is several GB): time,
/// peak memory and disk per step, through the same model the app uses. Run by
/// `make bench`. RINGTONE_BENCH_FILES lists inputs, colon-separated, absolute or
/// relative to Documents (on a device). Disabled in a plain test run.
@MainActor
struct LargeFileBenchmarks {
    static let env = ProcessInfo.processInfo.environment
    static let files = (env["RINGTONE_BENCH_FILES"] ?? "").split(separator: ":").map(String.init)

    @Test(.enabled(if: !files.isEmpty))
    func bigInputs() async throws {
        UserDefaults.standard.set(false, forKey: EditorModel.iCloudKey)
        let model = EditorModel()
        let sampler = PeakSampler()
        var exported: [URL] = []
        print("BENCH start footprint=\(mb(footprint()))MB freeDisk=\(mb(UInt64(freeDisk())))MB")

        for path in Self.files {
            let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : URL.documentsDirectory.appendingPathComponent(path)
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            let freeBefore = freeDisk()

            let load = await measure(sampler) { await model.load(url) }
            #expect(model.errorMessage == nil, "\(path): \(model.errorMessage ?? "")")
            let freeAfterLoad = freeDisk()

            // Started by `load`; measured from when the editor is already usable:
            // first bars on screen, then the whole waveform.
            let deadline = Date().addingTimeInterval(1_800)
            let firstBars = try await measure(sampler) {
                while model.levels.isEmpty, model.isReadingWaveform, Date() < deadline {
                    try await Task.sleep(for: .milliseconds(10))
                }
            }
            let wave = try await measure(sampler) {
                while model.isReadingWaveform, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
            }
            #expect(!model.levels.isEmpty && !model.levels.contains { $0.isNaN }, "\(path): no waveform")

            model.selection.shift(to: model.selection.duration / 2)
            var output: URL?
            let export = await measure(sampler) { output = await model.export() }
            #expect(output != nil, "\(path): export failed")
            exported += output.map { [$0] } ?? []

            let preview = try await measure(sampler) {
                model.togglePreview()
                try await Task.sleep(for: .seconds(3))
            }
            #expect(model.isPlaying, "\(path): preview stopped early")
            model.stopPreview()

            // Earlier sources must be gone: each can be a multi-GB video.
            let tmp = directorySize(FileManager.default.temporaryDirectory)
            #expect(tmp < UInt64(size) + 100 * 1_048_576, "\(path): tmp holds \(mb(tmp))MB")

            print("""
                BENCH \(url.lastPathComponent) size=\(mb(UInt64(size)))MB \
                duration=\(Int(model.selection.duration))s \
                load=\(load) firstBars=\(firstBars) wave=\(wave) export=\(export) preview=\(preview) \
                footprint=\(mb(footprint()))MB tmp=\(mb(tmp))MB \
                diskUsedByLoad=\(mb(UInt64(max(0, freeBefore - freeAfterLoad))))MB
                """)
        }

        for url in exported { try? FileManager.default.removeItem(at: url) }
        // Inputs copied onto a phone only for this run; devicectl cannot delete them.
        if Self.env["RINGTONE_BENCH_DELETE_INPUTS"] == "1" {
            for path in Self.files where !path.hasPrefix("/") {
                let input = URL.documentsDirectory.appendingPathComponent(path)
                try? FileManager.default.removeItem(at: input)
                // The folder they came in would otherwise linger in the Files app.
                let folder = input.deletingLastPathComponent()
                if folder.standardizedFileURL != URL.documentsDirectory.standardizedFileURL,
                   (try? FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty) == true {
                    try? FileManager.default.removeItem(at: folder)
                }
            }
        }
        print("BENCH end footprint=\(mb(footprint()))MB")
        if let seconds = Self.env["RINGTONE_BENCH_HOLD"].flatMap(Double.init) {
            // Lets the script run `leaks` against this process while everything is still loaded.
            print("BENCH hold pid=\(getpid())")
            try await Task.sleep(for: .seconds(seconds))
        }
    }

    private func measure(_ sampler: PeakSampler, _ body: () async throws -> Void) async rethrows -> String {
        _ = sampler.take()
        let start = Date()
        try await body()
        let seconds = Date().timeIntervalSince(start)
        return String(format: "%.2fs/%dMB", seconds, mb(sampler.take()))
    }
}

/// Highest footprint seen since the last `take`, sampled every 10 ms off the main thread.
private final class PeakSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var peak: UInt64 = 0
    private let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "bench.sampler"))

    init() {
        timer.schedule(deadline: .now(), repeating: .milliseconds(10))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let now = footprint()
            lock.lock()
            peak = max(peak, now)
            lock.unlock()
        }
        timer.resume()
    }

    deinit { timer.cancel() }

    func take() -> UInt64 {
        lock.lock()
        defer { peak = footprint(); lock.unlock() }
        return max(peak, footprint())
    }
}

/// The figure jetsam judges the app by.
private func footprint() -> UInt64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? info.phys_footprint : 0
}

private func freeDisk() -> Int64 {
    let values = try? URL.temporaryDirectory.resourceValues(forKeys: [.volumeAvailableCapacityKey])
    return Int64(values?.volumeAvailableCapacity ?? 0)
}

private func directorySize(_ url: URL) -> UInt64 {
    let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey]
    guard let items = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) else { return 0 }
    var total: UInt64 = 0
    for case let item as URL in items {
        total += UInt64((try? item.resourceValues(forKeys: Set(keys)).totalFileAllocatedSize) ?? 0)
    }
    return total
}

private func mb(_ bytes: UInt64) -> Int { Int(bytes / 1_048_576) }
