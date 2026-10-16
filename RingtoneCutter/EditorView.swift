import SwiftUI

struct EditorView: View {
    @Bindable var model: EditorModel
    @State private var isNaming = false
    @State private var draftName = ""
    @AppStorage(EditorModel.iCloudKey) private var saveToICloud = false

    var body: some View {
        VStack(spacing: 16) {
            header
            WaveformSelector(levels: model.levels, selection: $model.selection, playhead: model.playhead)
            timeControls
            Spacer(minLength: 0)
            Toggle(isOn: $model.fades) {
                Label("淡入淡出", systemImage: "speaker.wave.2")
                Text("鈴聲開頭漸強、結尾漸弱")
            }
            .tint(.accentColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) { exportBar }
        .sensoryFeedback(.success, trigger: model.exportCount)
        // Named at the moment of making it: the name only matters once there is a
        // ringtone, and it is what the system ringtone list will show.
        .alert("鈴聲名稱", isPresented: $isNaming) {
            TextField("鈴聲名稱", text: $draftName)
            Button("取消", role: .cancel) {}
            Button("製作") {
                model.ringtoneName = draftName
                Task {
                    if let url = await model.export() { ShareSheet.present(url) }
                }
            }
            .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("這個名稱會顯示在 iPhone 的鈴聲清單中")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.ringtoneName)
                .font(.title2.bold())
                .lineLimit(1)
            Text("\(model.sourceName) · \(TimeText.string(model.selection.duration))")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var timeControls: some View {
        HStack(alignment: .center) {
            timeColumn(String(localized: "開始"), value: model.selection.start) { model.selection.setStart(model.selection.start + $0) }
            Spacer()
            VStack(spacing: 6) {
                playButton
                Text("\(String(format: "%.1f", model.selection.length)) / \(Int(TrimSelection.maxLength)) 秒")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            timeColumn(String(localized: "結束"), value: model.selection.end) { model.selection.setEnd(model.selection.end + $0) }
        }
    }

    private func timeColumn(_ title: String, value: Double, nudge: @escaping (Double) -> Void) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(TimeText.string(value))
                .font(.title3.monospacedDigit())
            HStack(spacing: 16) {
                Button { nudge(-0.1) } label: {
                    Image(systemName: "minus.circle.fill")
                }
                .accessibilityLabel("\(title)提早 0.1 秒")
                Button { nudge(0.1) } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .accessibilityLabel("\(title)延後 0.1 秒")
            }
            .font(.title2)
            // Glyph in the text colour, disc in yellow: a yellow glyph on a pale
            // yellow disc washes out in light mode.
            .symbolRenderingMode(.palette)
            .foregroundStyle(.primary, Color.accentColor.opacity(0.35))
            .buttonRepeatBehavior(.enabled)
        }
    }

    private var playButton: some View {
        Button {
            model.togglePreview()
        } label: {
            // Dark glyph on solid yellow: a yellow glyph on a pale yellow disc
            // all but disappears in light mode.
            Image(systemName: model.isPlaying ? "stop.fill" : "play.fill")
                .font(.title)
                .foregroundStyle(.black)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 64, height: 64)
                .background(Color.accentColor, in: Circle())
        }
        .accessibilityLabel(model.isPlaying ? Text("停止試聽") : Text("試聽片段"))
        .accessibilityIdentifier("play")
        .disabled(model.selection.length <= 0)
    }

    private var exportBar: some View {
        VStack(spacing: 8) {
            Button {
                draftName = model.ringtoneName
                isNaming = true
            } label: {
                Group {
                    if model.isExporting {
                        ProgressView()
                    } else {
                        Label("製作鈴聲", systemImage: "bell.and.waves.left.and.right")
                    }
                }
                .frame(maxWidth: .infinity)
                // White on yellow is unreadable; black holds up in both appearances.
                .foregroundStyle(.black)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("makeRingtone")
            .disabled(model.isExporting || model.selection.length <= 0)

            if let url = model.exportedURL {
                HStack(spacing: 4) {
                    Image(systemName: model.savedToICloud ? "icloud.fill" : "checkmark.circle.fill")
                        .foregroundStyle(model.savedToICloud ? Color.accentColor : .green)
                    Group {
                        if model.savedToICloud {
                            Text("已存到 iCloud 雲碟「\(url.lastPathComponent)」")
                        } else {
                            Text("已存成「\(url.lastPathComponent)」")
                        }
                    }
                    .lineLimit(1)
                    .truncationMode(.middle)
                    ShareLink("再次分享", item: url)
                }
                .font(.footnote)
                if saveToICloud && !model.savedToICloud {
                    Label("iCloud 雲碟無法使用，已存在這台 iPhone。", systemImage: "exclamationmark.icloud")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
            Text(ringtoneHint)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(.bar)
    }

    private var ringtoneHint: LocalizedStringKey {
        if #available(iOS 26, *) {
            "在分享選單點「用作鈴聲」即可設定。"
        } else {
            "此 iOS 版本無法直接設為鈴聲（需 iOS 26）。檔案會存在「檔案」App 的「鈴聲剪輯」資料夾。"
        }
    }
}
