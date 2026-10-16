import Foundation

/// Downloads a pasted link to a temporary file, reporting progress as it goes.
final class LinkDownloader: NSObject, URLSessionDownloadDelegate {
    enum DownloadError: LocalizedError {
        case notAFile
        case tooLarge
        case status(Int)

        var errorDescription: String? {
            switch self {
            case .notAFile:
                String(localized: "這個連結打開的是網頁，不是檔案。請確認已設為「知道連結的人都能檢視」，或改貼直接下載的網址。")
            case .tooLarge:
                String(localized: "檔案超過 500 MB，請改用較小的檔案。")
            case .status(let code):
                String(localized: "伺服器回應錯誤（\(code)），請確認連結是否仍然有效、已公開分享。")
            }
        }
    }

    /// A song is a few megabytes and a screen recording a few hundred; anything
    /// past this is almost certainly not what the user meant to turn into a ringtone.
    static let maxBytes: Int64 = 500 * 1_024 * 1_024

    private let onProgress: (Double?) -> Void
    private var continuation: CheckedContinuation<URL, Error>?

    /// `onProgress` gets the fraction done, or nil while the size is unknown.
    init(onProgress: @escaping (Double?) -> Void) {
        self.onProgress = onProgress
    }

    func download(_ url: URL) async throws -> URL {
        // Ephemeral: no cookies or cache are kept from one link to the next.
        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withTaskCancellationHandler {
            // Cancelled before starting: the handler has already invalidated the
            // session, and creating a task on it would raise.
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                session.downloadTask(with: url).resume()
            }
        } onCancel: {
            session.invalidateAndCancel()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > Self.maxBytes || totalBytesExpectedToWrite > Self.maxBytes {
            finish(.failure(DownloadError.tooLarge))
            downloadTask.cancel()
            return
        }
        onProgress(totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : nil)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // `location` is deleted when this method returns, so everything happens here.
        guard let response = downloadTask.response as? HTTPURLResponse else {
            finish(.failure(DownloadError.status(0)))
            return
        }
        guard (200..<300).contains(response.statusCode) else {
            finish(.failure(DownloadError.status(response.statusCode)))
            return
        }
        // A private or login-walled share answers 200 with a sign-in or preview page.
        if response.mimeType?.lowercased().hasPrefix("text/") == true {
            finish(.failure(DownloadError.notAFile))
            return
        }
        do {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            // Content-Disposition carries the real name for cloud drives; the URL's
            // last component is a file ID there.
            let name = response.suggestedFilename ?? response.url?.lastPathComponent ?? "audio"
            let destination = folder.appendingPathComponent(name)
            try FileManager.default.moveItem(at: location, to: destination)
            finish(.success(destination))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
    }

    /// Delegate calls arrive on the session's serial queue; the first outcome wins.
    private func finish(_ result: Result<URL, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}
