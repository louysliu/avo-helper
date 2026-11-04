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
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: AppRoute.crop) {
                    Label("裁剪", systemImage: "crop")
                }
                .disabled(session.artifact == nil)
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

