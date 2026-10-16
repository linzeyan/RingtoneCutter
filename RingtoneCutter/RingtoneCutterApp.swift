import SwiftUI

@main
struct RingtoneCutterApp: App {
    init() {
        // The editor always starts empty, so nothing in tmp outlives a launch, and a
        // source copy left there can be a multi-GB video the system may keep for days.
        let tmp = FileManager.default.temporaryDirectory
        for item in (try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)) ?? [] {
            try? FileManager.default.removeItem(at: item)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
