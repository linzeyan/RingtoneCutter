import SwiftUI

/// Paste a share link from a cloud drive, or any direct download address.
struct LinkImportView: View {
    let onDownload: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://…", text: $text, axis: .vertical)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .lineLimit(1...4)
                    // PasteButton reads the clipboard without the "Allow Paste?" prompt
                    // a programmatic read would trigger.
                    PasteButton(payloadType: String.self) { strings in
                        Task { @MainActor in text = strings.first ?? "" }
                    }
                    .buttonBorderShape(.capsule)
                    .labelStyle(.titleAndIcon)
                } footer: {
                    Text("支援 Google 雲端硬碟、Dropbox、OneDrive 的公開分享連結，以及 S3 等可以直接下載的網址。")
                }
            }
            .navigationTitle("貼上連結")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("下載") {
                        onDownload(text)
                        dismiss()
                    }
                    .disabled(CloudLink.url(in: text) == nil)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
