import SwiftUI
import UniformTypeIdentifiers

enum SupportedFormats {
    /// `.audio` alone misses formats whose system type does not conform to it on every
    /// iOS version, so the extensions AVFoundation was measured to decode are listed too.
    static let contentTypes: [UTType] = [.audio, .audiovisualContent]
        + ["opus", "ogg", "oga", "flac", "m4b", "ac3", "eac3", "caf"].compactMap { UTType(filenameExtension: $0) }

    static let summary = String(localized: "支援 MP3、M4A、AAC、WAV、AIFF、FLAC、ALAC、Opus、AC-3，以及 MP4、MOV 影片的聲音")
}

struct ContentView: View {
    @State private var model = EditorModel()
    @State private var isImporting = false

    var body: some View {
        NavigationStack {
            Group {
                if model.sourceURL == nil {
                    emptyState
                } else {
                    EditorView(model: model)
                        .toolbar {
                            Button("換一首", systemImage: "music.note.list") { isImporting = true }
                        }
                }
            }
            .navigationTitle("鈴聲剪輯")
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if model.isLoading {
                    ProgressView("讀取中…")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: SupportedFormats.contentTypes) { result in
            switch result {
            case .success(let url): Task { await model.load(url) }
            case .failure(let error): model.errorMessage = error.localizedDescription
            }
        }
        // "Open in 鈴聲剪輯" from Files, Mail, LINE and other apps.
        .onOpenURL { url in Task { await model.load(url) } }
        #if DEBUG
        // `-openFile <path>` launches straight into the editor for screenshots,
        // skipping the document picker that automation cannot drive reliably.
        .task {
            if let path = UserDefaults.standard.string(forKey: "openFile") {
                await model.load(URL(fileURLWithPath: path))
            }
        }
        #endif
        .alert("發生錯誤", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("好") {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label {
                Text("製作 iPhone 鈴聲")
            } icon: {
                Image(systemName: "bell.and.waves.left.and.right")
                    .foregroundStyle(Color.accentColor)
            }
        } description: {
            Text("選一首歌，剪下 30 秒以內的片段")
        } actions: {
            Button {
                isImporting = true
            } label: {
                Label("選擇音檔", systemImage: "music.note")
                    .padding(.horizontal, 8)
                    .foregroundStyle(.black)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.isLoading)
        }
        .safeAreaInset(edge: .bottom) {
            Text(SupportedFormats.summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 16)
        }
    }
}
