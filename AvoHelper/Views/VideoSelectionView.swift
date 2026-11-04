import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct VideoSelectionView: View {
    @Bindable var video: VideoStitchingSession
    let session: StitchingSession
    @State private var showFiles = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if video.inputURL == nil {
                    ContentUnavailableView {
                        Label("选择滚动录屏", systemImage: "video.badge.plus")
                    } description: {
                        Text("导入一段滚动浏览页面的录屏，生成可裁剪、保存的长截图。")
                    }
                } else {
                    if let image = video.thumbnail {
                        Image(uiImage: image).resizable().scaledToFit()
                            .frame(maxHeight: 250)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    VStack(spacing: 6) {
                        Text(video.inputName).font(.headline).lineLimit(2)
                        Text(Duration.seconds(video.duration).formatted(.time(pattern: .minuteSecond)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    PhotosPicker(selection: $video.pickerItem, matching: .videos) {
                        Label("从相册选择", systemImage: "photo.on.rectangle")
                    }
                    Button { showFiles = true } label: {
                        Label("从文件选择", systemImage: "folder")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(video.isBusy)

                Text(video.algorithm.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if video.isProcessing {
                    VStack(spacing: 12) {
                        ProgressView(value: video.progress.fraction)
                        Text(video.progress.message).font(.footnote).foregroundStyle(.secondary)
                        Button("取消转换", role: .cancel) { video.cancel() }
                            .disabled(video.isCancelling)
                    }
                    .accessibilityIdentifier("video-processing")
                } else if video.isImporting {
                    ProgressView("正在读取视频…")
                } else if let status = video.status {
                    Text(status).font(.footnote).foregroundStyle(.secondary)
                }
                Text("录屏应保留相邻画面的重叠。快速滑动、动画或重复内容可能导致分段，请检查生成结果。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("视频转长截图")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("转换算法", selection: $video.algorithm) {
                        ForEach(VideoAlgorithm.allCases) { algorithm in
                            Text(algorithm.title).tag(algorithm)
                        }
                    }
                } label: {
                    Label("更多选项", systemImage: "ellipsis.circle")
                }
                .accessibilityIdentifier("video-algorithm-menu")
                .disabled(video.isBusy)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                Task { await video.convert(into: session) }
            } label: {
                Label("生成长截图", systemImage: "rectangle.portrait.and.arrow.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(video.inputURL == nil || video.isBusy)
            .padding().background(.bar)
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.movie], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { Task { await video.importFile(url) } }
            case .failure(let error):
                video.message = UserMessage(title: "无法选择视频", message: error.localizedDescription)
            }
        }
        .onChange(of: video.pickerItem) { _, item in
            if let item { Task { await video.importPhoto(item) } }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { video.cancel() }
        }
        .alert(item: $video.message) { message in
            Alert(title: Text(message.title), message: Text(message.message), dismissButton: .default(Text("好")))
        }
    }
}
