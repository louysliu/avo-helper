import SwiftUI

struct RootView: View {
    @State private var session = StitchingSession()
    @State private var video = VideoStitchingSession()

    var body: some View {
        RootNavigationView(session: session, video: video)
    }
}

private struct RootNavigationView: View {
    @Bindable var session: StitchingSession
    @Bindable var video: VideoStitchingSession

    var body: some View {
        NavigationStack(path: $session.path) {
            Group {
                switch session.workflow {
                case .screenshots: SelectionView(session: session)
                case .video: VideoSelectionView(video: video, session: session)
                }
            }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Picker("选择功能", selection: $session.workflow) {
                                ForEach(AppWorkflow.allCases) { workflow in
                                    Label(workflow.title, systemImage: workflow.symbol).tag(workflow)
                                }
                            }
                        } label: {
                            Label("切换功能", systemImage: "line.3.horizontal")
                        }
                        .accessibilityIdentifier("workflow-menu")
                        .disabled(session.isProcessing || session.isLoadingSelection || video.isBusy)
                    }
                }
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .result:
                        ResultView(session: session)
                    case .crop:
                        if let image = session.artifact?.preview {
                            CropEditorView(
                                image: image,
                                initialCrop: session.crop,
                                onApply: session.applyCrop
                            )
                        }
                    }
                }
        }
        .alert(item: $session.message) { message in
            Alert(
                title: Text(message.title),
                message: Text(message.message),
                dismissButton: .default(Text("好"))
            )
        }
    }
}

#Preview("选择截图") {
    RootView()
}

