import SwiftUI
import RealityKit

@main
struct AppleSpiralApp: App {
    init() {
        // Registra os componentes e o sistema de flutuação no RealityKit.
        FloatComponent.registerComponent()
        FruitTag.registerComponent()
        SeedComponent.registerComponent()
        FloatSystem.registerSystem()
    }

    var body: some SwiftUI.Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 1.0, height: 0.8, depth: 0.8, in: .meters)
    }
}
