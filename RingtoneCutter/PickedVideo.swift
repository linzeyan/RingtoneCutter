import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// A video handed over by the Photos picker. The system deletes the file it passes in
/// once the import closure returns, so it is copied somewhere the editor can keep using.
struct PickedVideo: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            // A folder per import keeps two picks with the same name (IMG_0001.MOV) apart.
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let copy = folder.appendingPathComponent(received.file.lastPathComponent)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedVideo(url: copy)
        }
    }
}
