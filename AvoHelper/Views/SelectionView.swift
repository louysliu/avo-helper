import PhotosUI
import SwiftUI

struct SelectionView: View {
    @Bindable var session: StitchingSession

    var body: some View {
        Group {
            if session.screenshots.isEmpty {
                emptyState
            } else {
                screenshotList
            }
        }
        .navigationTitle("Avo Helper")
        .toolbar {
            if !session.screenshots.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    photoPickerLabel(title: "添加", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("拼接算法", selection: $session.algorithm) {
                        ForEach(AppStitchAlgorithm.allCases) { algorithm in
                            Text(algorithm.title).tag(algorithm)
                        }
                    }
                } label: {
                    Label("更多选项", systemImage: "ellipsis.circle")
                }
                .disabled(session.isLoadingSelection || session.isProcessing)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !session.screenshots.isEmpty {
                stitchButton
            }
        }
        .overlay {
            if session.isLoadingSelection {
                LoadingOverlay(title: "正在读取截图…")
            } else if session.isProcessing {
                LoadingOverlay(title: "正在去重拼接…")
            }
        }
        .onChange(of: session.pickerItems) { _, items in
            Task { await session.synchronizePickerItems(items) }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("选择滚动截图", systemImage: "rectangle.stack.badge.plus")
        } description: {
            Text("按从上到下的顺序选择 2–10 张截图，Avo Helper 会自动去掉重复区域。")
        } actions: {
            photoPickerLabel(title: "选择截图", systemImage: "photo.on.rectangle.angled")
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding()
    }

    private var screenshotList: some View {
        List {
            Section {
                ForEach(Array(session.screenshots.enumerated()), id: \.element.id) { index, screenshot in
                    ScreenshotRow(index: index, screenshot: screenshot)
                }
                .onDelete(perform: session.removeScreenshots)
                .onMove(perform: session.moveScreenshots)
            } header: {
                Text("拼接顺序")
            } footer: {
                Text("拖动可调整顺序。系统会比较每张截图的底部与下一张的顶部。")
            }
        }
        .listStyle(.insetGrouped)
    }

    private var stitchButton: some View {
        VStack(spacing: 8) {
            Button {
                Task { await session.stitch() }
            } label: {
                Label("开始拼接", systemImage: "rectangle.stack")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!session.canStitch)

            if session.screenshots.count < 2 {
                Text("还需选择至少一张截图")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background(.bar)
    }

    private func photoPickerLabel(title: String, systemImage: String) -> some View {
        PhotosPicker(
            selection: $session.pickerItems,
            maxSelectionCount: 10,
            selectionBehavior: .ordered,
            matching: .images
        ) {
            Label(title, systemImage: systemImage)
        }
        .disabled(session.isLoadingSelection || session.isProcessing)
    }
}

private struct ScreenshotRow: View {
    let index: Int
    let screenshot: SelectedScreenshot

    var body: some View {
        HStack(spacing: 14) {
            Image(uiImage: screenshot.image)
                .resizable()
                .scaledToFill()
                .frame(width: 54, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.quaternary, lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text("截图 \(index + 1)")
                    .font(.headline)
                Text("\(Int(screenshot.image.size.width * screenshot.image.scale)) × \(Int(screenshot.image.size.height * screenshot.image.scale)) 像素")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("第 \(index + 1) 张截图")
    }
}

struct LoadingOverlay: View {
    let title: String

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text(title)
                .font(.headline)
        }
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .shadow(radius: 16, y: 6)
        .accessibilityElement(children: .combine)
    }
}

