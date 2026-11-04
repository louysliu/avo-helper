import SwiftUI

struct RootView: View {
    @State private var session = StitchingSession()

    var body: some View {
        RootNavigationView(session: session)
    }
}

private struct RootNavigationView: View {
    @Bindable var session: StitchingSession

    var body: some View {
        NavigationStack(path: $session.path) {
            SelectionView(session: session)
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

