import SwiftUI

@main
struct MacrowaversApp: App {
    @State private var appModel = AppModel()
    /// Feature "Untangle the Dragon" (AR126-100): un solo ViewModel condiviso da pannello e spazio immersivo.
    @State private var untangleViewModel = UntangleViewModel()

    init() {
        DragonBodySystem.registerAll()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
        }

        WindowGroup(id: ControlPanelView.windowID) {
            ControlPanelView()
                .environment(untangleViewModel)
        }
        .windowResizability(.contentSize)

        ImmersiveSpace(id: DragonImmersiveView.spaceID) {
            DragonImmersiveView()
                .environment(untangleViewModel)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
