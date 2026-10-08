#if os(visionOS)
import RealityKit
import SwiftUI

/// Spazio immersivo in mixed reality: il drago aggrovigliato appare davanti all'utente,
/// che continua a vedere l'ambiente reale intorno.
struct DragonImmersiveView: View {
    static let spaceID = "DragonSpace"

    @Environment(UntangleViewModel.self) private var viewModel
    /// Posizione/rotazione della piattaforma all'inizio del gesto in corso.
    @State private var moveStart: SIMD3<Float>?
    @State private var yawStart: Float?
    /// Iscrizioni agli eventi di presa sul drago: vanno tenute vive finché la view esiste.
    @State private var subscriptions: [EventSubscription] = []
    /// Posizione della testa dell'utente: il drago guarda il cavaliere.
    @State private var viewer = ViewerTracker()

    var body: some View {
        RealityView { content in
            content.add(await DragonSceneBuilder.makePlayArea(viewModel: viewModel, viewer: viewer))
            subscriptions = subscribeToDragonGrabs(content)
        } update: { content in
            // Leggere `placement` qui fa ri-eseguire questo blocco a ogni cambio.
            let placement = viewModel.placement
            guard let playArea = content.entities.first(where: { $0.name == DragonSceneBuilder.playAreaName }) else { return }
            playArea.position = placement.position
            playArea.orientation = placement.rotation
        }
        .gesture(moveGesture)
        .simultaneousGesture(rotateGesture)
        .task { await viewer.start() }
        .onAppear { viewModel.immersiveSpaceState = .open }
        .onDisappear {
            viewer.stop()
            viewModel.immersiveSpaceState = .closed
        }
    }

    // MARK: - Drago

    /// Ogni nodo del drago ha un `ManipulationComponent`: ogni mano afferra e muove il proprio nodo,
    /// quindi si possono tenere due parti del corpo contemporaneamente.
    /// Qui si avvisa il ViewModel di inizio/fine presa; il movimento lo legge il `DragonBodySystem`.
    private func subscribeToDragonGrabs(_ content: RealityViewContent) -> [EventSubscription] {
        [
            content.subscribe(to: ManipulationEvents.WillBegin.self) { event in
                guard let node = event.entity.components[DragonNodeComponent.self] else { return }
                viewModel.grab(node: node.index)
            },
            content.subscribe(to: ManipulationEvents.WillRelease.self) { event in
                guard let node = event.entity.components[DragonNodeComponent.self] else { return }
                viewModel.release(node: node.index)
            },
            // Sicurezza: se la presa termina senza rilascio (es. annullata), il nodo va comunque liberato.
            content.subscribe(to: ManipulationEvents.WillEnd.self) { event in
                guard let node = event.entity.components[DragonNodeComponent.self] else { return }
                viewModel.release(node: node.index)
            },
        ]
    }

    // MARK: - Piattaforma

    /// Pizzica la piattaforma o la maniglia e spostala (anche in altezza).
    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .targetedToEntity(where: .has(PlayAreaHandleComponent.self))
            .onChanged { value in
                let start = moveStart ?? viewModel.placement.position
                moveStart = start
                let from = value.convert(value.startLocation3D, from: .local, to: .scene)
                let to = value.convert(value.location3D, from: .local, to: .scene)
                viewModel.movePlayArea(to: start + (to - from))
            }
            .onEnded { _ in
                moveStart = nil
            }
    }

    /// Ruota la piattaforma con due mani (nel simulatore: tieni premuto Option).
    private var rotateGesture: some Gesture {
        RotateGesture3D(constrainedToAxis: .y)
            .targetedToEntity(where: .has(PlayAreaHandleComponent.self))
            .onChanged { value in
                let start = yawStart ?? viewModel.placement.yaw
                yawStart = start
                let quaternion = value.rotation.quaternion
                let angle = Float(2 * atan2(quaternion.imag.y, quaternion.real))
                // Lo spazio SwiftUI ha la y verso il basso: segno invertito rispetto a RealityKit.
                viewModel.rotatePlayArea(yaw: start - angle)
            }
            .onEnded { _ in
                yawStart = nil
            }
    }
}

#Preview(immersionStyle: .mixed) {
    DragonImmersiveView()
        .environment(UntangleViewModel())
}
#endif
