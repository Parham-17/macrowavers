import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(spacing: 24) {
            Text("Sky and the Planets")
                .font(.extraLargeTitle)
            Text(statusText)
                .font(.title2)
                .foregroundStyle(.secondary)
            Button(buttonTitle, action: primaryAction)
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
