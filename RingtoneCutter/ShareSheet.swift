import UIKit

/// Presents the system share sheet right after export, which saves a tap over a
/// ShareLink that only appears once the file exists.
@MainActor
enum ShareSheet {
    static func present(_ url: URL) {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
            var top = scene.keyWindow?.rootViewController
        else { return }
        // The naming alert may still be animating out; presenting on it would fail.
        while let presented = top.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        top.present(UIActivityViewController(activityItems: [url], applicationActivities: nil), animated: true)
    }
}
