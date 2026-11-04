import SwiftUI

struct ResultView: View {
    @Bindable var session: StitchingSession

    var body: some View {
        VStack(spacing: 0) {
            if let name = session.artifact?.algorithmName {
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            }
            if !session.warningSeams.isEmpty {
                warningBanner
            }
            if !session.videoImages.isEmpty {
                videoResultSummary
            }
            preview
        }
        .navigationTitle("拼接结果")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("重新选择") {
                    session.startOver()
                }
                .disabled(session.isExporting)
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: AppRoute.crop) {
                    Label("裁剪", systemImage: "crop")
                }
                .disabled(session.artifact == nil || session.isExporting)
            }
        }
        .safeAreaInset(edge: .bottom) {
            exportBar
        }
        .overlay {
            if session.isExporting {
                LoadingOverlay(title: "正在准备文件…")
            }
        }
        .sheet(item: $session.shareItem) { item in
            ShareSheet(items: [item.url]) {
                session.finishSharing(item)
            }
        }
    }

    private var videoResultSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            if session.videoImages.count > 1 {
                Picker("查看片段", selection: Binding(get: { session.selectedVideoImage }, set: session.selectVideoImage)) {
                    ForEach(session.videoImages.indices, id: \.self) { index in
                        Text("片段 \(index + 1) / \(session.videoImages.count)").tag(index)
                    }
                }
                .pickerStyle(.menu)
                .disabled(session.isExporting)
                Text("片段未强行连接。裁剪、保存和导出仅针对当前片段；切换片段会重置裁剪。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if session.videoIsPartial {
                Label("结果可能不完整，请检查是否缺少内容。", systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(.orange)
            }
            if !session.videoWarnings.isEmpty {
                DisclosureGroup("转换提示（\(session.videoWarnings.count)）") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(session.videoWarnings.enumerated()), id: \.offset) { _, warning in
                                Text(warning).font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }.frame(maxHeight: 140)
                }
                .font(.footnote)
            }
        }
        .padding(.horizontal).padding(.vertical, 6)
    }

    private var warningBanner: some View {
        Label {
            Text("有 \(session.warningSeams.count) 处未识别到重叠，已完整保留内容。")
                .font(.footnote)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .foregroundStyle(.orange)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.10))
    }

    private var preview: some View {
        GeometryReader { proxy in
            ScrollView([.vertical, .horizontal]) {
                if let image = session.croppedPreview {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: min(max(260, proxy.size.width - 32), 720))
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                        .padding(16)
                        .accessibilityLabel("拼接长图预览")
                }
            }
            .background(Color(uiColor: .secondarySystemBackground))
        }
    }

    private var exportBar: some View {
        HStack(spacing: 12) {
            Button {
                Task { await session.saveToPhotos() }
            } label: {
                Label("存到相册", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button {
                Task { await session.preparePDFShare() }
            } label: {
                Label("导出 PDF", systemImage: "doc.richtext")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .disabled(session.isExporting)
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background(.bar)
    }
}

