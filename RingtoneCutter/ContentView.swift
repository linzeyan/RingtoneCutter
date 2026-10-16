import PhotosUI
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
    @State private var isPickingVideo = false
    @AppStorage(EditorModel.iCloudKey) private var saveToICloud = false
    @State private var pickedVideo: PhotosPickerItem?
    @State private var isPastingLink = false
    @State private var isExplainingSaveLocation = false

    var body: some View {
        NavigationStack {
            Group {
                if model.sourceURL == nil {
                    emptyState
                } else {
                    EditorView(model: model)
                }
            }
            .toolbar {
                // The empty state already shows these as buttons.
                if model.sourceURL != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button("選擇檔案", systemImage: "music.note") { isImporting = true }
                            Button("選擇影片", systemImage: "video") { isPickingVideo = true }
                            Button("貼上連結", systemImage: "link") { isPastingLink = true }
                        } label: {
                            Label("換一首", systemImage: "music.note.list")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    saveLocation
                }
            }
            .navigationTitle("鈴聲剪輯")
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if model.isDownloading {
                    VStack(spacing: 16) {
                        if let progress = model.downloadProgress {
                            ProgressView("下載中…", value: progress)
                                .frame(width: 180)
                        } else {
                            ProgressView("下載中…")
                        }
                        Button("取消", role: .cancel) { model.cancelDownload() }
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                } else if model.isLoading {
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
        // The system picker hands over only the chosen video, so no Photos
        // permission is requested; screen recordings land here too.
        .photosPicker(isPresented: $isPickingVideo, selection: $pickedVideo, matching: .videos)
        .onChange(of: pickedVideo) {
            guard let item = pickedVideo else { return }
            pickedVideo = nil
            Task { await model.loadVideo(item) }
        }
        .sheet(isPresented: $isPastingLink) {
            LinkImportView { model.loadLink($0) }
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

    /// Always in view, so where the next ringtone goes is never a surprise.
    private var saveLocation: some View {
        // Info first, so the switch itself sits at the trailing edge.
        HStack(spacing: 6) {
            Button {
                isExplainingSaveLocation = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("儲存位置說明")
            .popover(isPresented: $isExplainingSaveLocation) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("儲存位置").font(.headline)
                    Label("這台 iPhone：存在「檔案」→「我的 iPhone」→「鈴聲剪輯」。刪除 App 時會一起刪除。", systemImage: "iphone")
                    Label("iCloud 雲碟：存在 iCloud 雲碟的「鈴聲剪輯」資料夾，其他 iPhone、iPad、Mac 也拿得到。", systemImage: "icloud")
                    Text("iPhone 的鈴聲清單不會跨裝置同步：在另一台 iPhone 上，從「檔案」打開鈴聲，再點「用作鈴聲」。")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .padding()
                .frame(width: 300)
                // A popover rather than a sheet: a few lines anchored to the switch
                // they explain.
                .presentationCompactAdaptation(.popover)
            }
            Picker("儲存位置", selection: $saveToICloud) {
                segmentIcon("iphone", selected: !saveToICloud)
                    .accessibilityLabel("這台 iPhone")
                    .tag(false)
                segmentIcon("icloud", selected: saveToICloud)
                    .accessibilityLabel("iCloud 雲碟")
                    .tag(true)
            }
            .pickerStyle(.segmented)
            .fixedSize()
        }
    }

    /// The chosen side in the app's yellow. The segmented control ignores SwiftUI
    /// foreground styles but keeps an image's own colours, so the colour is baked in.
    private func segmentIcon(_ name: String, selected: Bool) -> Image {
        let symbol = UIImage(systemName: name) ?? UIImage()
        guard selected, let accent = UIColor(named: "AccentColor") else { return Image(uiImage: symbol) }
        return Image(uiImage: symbol.withTintColor(accent, renderingMode: .alwaysOriginal))
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
            VStack(spacing: 12) {
                Button {
                    isImporting = true
                } label: {
                    Label("選擇檔案", systemImage: "music.note")
                        .frame(maxWidth: 240)
                        .foregroundStyle(.black)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    isPickingVideo = true
                } label: {
                    Label("選擇影片", systemImage: "video")
                        .frame(maxWidth: 240)
                        // Yellow text on the pale bordered fill is unreadable in light mode.
                        // `Color.primary`, not `.primary`: inside a bordered button the
                        // hierarchical style resolves to the tint.
                        .foregroundStyle(Color.primary)
                }
                .buttonStyle(.bordered)

                Button {
                    isPastingLink = true
                } label: {
                    Label("貼上連結", systemImage: "link")
                        .frame(maxWidth: 240)
                        .foregroundStyle(Color.primary)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
            .disabled(model.isLoading || model.isDownloading)
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
