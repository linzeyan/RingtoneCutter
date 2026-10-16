import Foundation

/// Turns a pasted share link into an address that returns the file itself.
/// Share links from cloud drives open a preview page; each service has its own
/// way to ask for the raw file instead. Anything unrecognised is fetched as-is,
/// which covers direct links such as S3 public objects and presigned URLs.
enum CloudLink {
    /// The first https address in pasted text. Share sheets often wrap the link in
    /// a title or a message, so the whole clipboard is searched, not parsed as a URL.
    static func url(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range)
            .compactMap(\.url)
            .first { $0.scheme?.lowercased() == "https" }
    }

    static func downloadURL(for url: URL) -> URL {
        guard let host = url.host()?.lowercased() else { return url }

        if host == "drive.google.com" || host == "docs.google.com", let id = googleDriveID(url) {
            // confirm=t skips the "can't scan this file for viruses" page Google shows
            // for larger files, which would otherwise arrive instead of the audio.
            return URL(string: "https://drive.usercontent.google.com/download?id=\(id)&export=download&confirm=t")!
        }
        if host == "dropbox.com" || host.hasSuffix(".dropbox.com") {
            // rlkey and the rest of the query identify the shared file and must stay.
            return settingQuery(of: url, ["dl": "1"], removing: ["raw"])
        }
        if host == "1drv.ms" || host == "onedrive.live.com" {
            // OneDrive's shares API takes the share link itself, base64url-encoded.
            let encoded = Data(url.absoluteString.utf8).base64EncodedString()
                .replacingOccurrences(of: "=", with: "")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "+", with: "-")
            return URL(string: "https://api.onedrive.com/v1.0/shares/u!\(encoded)/root/content")!
        }
        if host.hasSuffix(".sharepoint.com") {
            return settingQuery(of: url, ["download": "1"], removing: [])
        }
        return url
    }

    /// `/file/d/<id>/view`, or `?id=<id>` on the older `open` and `uc` links.
    private static func googleDriveID(_ url: URL) -> String? {
        let parts = url.pathComponents
        if let d = parts.firstIndex(of: "d"), d + 1 < parts.count {
            return parts[d + 1]
        }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "id" }?.value
    }

    private static func settingQuery(of url: URL, _ values: [String: String], removing: Set<String>) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var items = (components.queryItems ?? []).filter {
            values[$0.name] == nil && !removing.contains($0.name)
        }
        items += values.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        components.queryItems = items
        return components.url ?? url
    }
}
