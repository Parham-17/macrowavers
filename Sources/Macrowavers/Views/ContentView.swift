import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 24) {
            Text("Macrowavers")
                .font(.extraLargeTitle)
            Text(statusText)
                .font(.title2)
                .foregroundStyle(.secondary)
            Button(buttonTitle, action: primaryAction)
            Button("Untangle the Dragon", systemImage: "lizard") {
                openWindow(id: ControlPanelView.windowID)
            }
        }
        .padding(48)
    }

    private var statusText: String {
        switch appModel.phase {
        case .menu: "Ready"
        case .playing: "Score \(appModel.score)"
        case .paused: "Paused"
        }
    }

    private var buttonTitle: String {
        switch appModel.phase {
        case .menu: "Start"
        case .playing: "Pause"
        case .paused: "Resume"
        }
    }

    private func primaryAction() {
        switch appModel.phase {
        case .menu: appModel.start()
        case .playing: appModel.pause()
        case .paused: appModel.resume()
        }
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
}
