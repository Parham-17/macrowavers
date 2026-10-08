import SwiftUI

/// Finestra di controllo: avvia lo spazio immersivo e mostra lo stato del puzzle.
struct ControlPanelView: View {
    static let windowID = "UntangleControlPanel"

    @Environment(UntangleViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 16) {
            #if os(visionOS)
            if viewModel.immersiveSpaceState == .open {
                status
            } else {
                Text("Untangle the Dragon")
                    .font(.extraLargeTitle2)
                Text("The dragon will appear in front of you, right in your room.")
                    .foregroundStyle(.secondary)
            }
            ImmersiveSpaceToggle()
            #else
            Text("This mini-game requires Apple Vision Pro.")
            #endif
        }
        .multilineTextAlignment(.center)
        .padding(32)
    }

    private var status: some View {
        VStack(spacing: 12) {
            if viewModel.isSolved {
                Text("The dragon is free! 🐉")
                    .font(.extraLargeTitle2)
                Text(viewModel.isFlying ? "Look around: it's flying all over the room!" : "It's spreading its wings…")
                    .foregroundStyle(.secondary)
            } else {
                Text("Crossings left: \(viewModel.crossingCount)")
                    .font(.title)
                    .contentTransition(.numericText())
                    .animation(.default, value: viewModel.crossingCount)
                Text(moodMessage)
                    .foregroundStyle(.secondary)
                ProgressView(value: Double(viewModel.restlessness))
                    .tint(.orange)
                    .opacity(viewModel.restlessness > 0 ? 1 : 0)
            }
            Button(viewModel.isSolved ? "Play Again" : "Restart", systemImage: "arrow.counterclockwise") {
                viewModel.reset()
            }
            Divider()
            placementControls
        }
    }

    private var moodMessage: String {
        switch viewModel.mood {
        case .calm: "Pinch and drag the dragon's body. You can use both hands."
        case .annoyed: "Easy! The dragon doesn't like being pulled!"
        case .restless: "The dragon is getting restless…"
        case .wriggling:
            switch viewModel.action {
            case .rearUp: "The dragon rears up and roars!"
            case .turn: "The dragon is turning around!"
            case .tailLash: "Watch out for its tail!"
            case .coil: "The dragon is coiling up!"
            case nil: "The dragon is thrashing!"
            }
        case .free: ""
        }
    }

    /// Alternativa ai gesti per sistemare la piattaforma (comoda anche nel simulatore).
    private var placementControls: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Tilt")
                Slider(value: Binding(get: { Double(viewModel.placement.tilt) },
                                      set: { viewModel.setTilt(Float($0)) }),
                       in: Double(PlayAreaPlacement.tiltRange.lowerBound)...Double(PlayAreaPlacement.tiltRange.upperBound))
            }
            HStack {
                Button("Rotate Left", systemImage: "rotate.left") {
                    viewModel.rotatePlayArea(yaw: viewModel.placement.yaw + .pi / 8)
                }
                Button("Rotate Right", systemImage: "rotate.right") {
                    viewModel.rotatePlayArea(yaw: viewModel.placement.yaw - .pi / 8)
                }
                Button("Reset Position", systemImage: "arrow.uturn.backward") {
                    viewModel.resetPlacement()
                }
            }
            .labelStyle(.iconOnly)
            Text("Drag the platform or its handle to move it. Rotate it with both hands.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

#if os(visionOS)
/// Apre e chiude lo spazio immersivo. Le azioni `openImmersiveSpace`/`dismissImmersiveSpace`
/// esistono solo nell'Environment di SwiftUI, quindi vivono nella View; lo stato è nel ViewModel.
private struct ImmersiveSpaceToggle: View {
    @Environment(UntangleViewModel.self) private var viewModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    var body: some View {
        Button(viewModel.immersiveSpaceState == .open ? "Close" : "Start") {
            Task { await toggle() }
        }
        .buttonStyle(.borderedProminent)
        .disabled(viewModel.immersiveSpaceState == .inTransition)
    }

    private func toggle() async {
        switch viewModel.immersiveSpaceState {
        case .open:
            viewModel.immersiveSpaceState = .inTransition
            // Lo stato torna `.closed` nell'onDisappear di DragonImmersiveView.
            await dismissImmersiveSpace()
        case .closed:
            viewModel.immersiveSpaceState = .inTransition
            switch await openImmersiveSpace(id: DragonImmersiveView.spaceID) {
            case .opened:
                // Lo stato diventa `.open` nell'onAppear di DragonImmersiveView.
                break
            case .userCancelled, .error:
                viewModel.immersiveSpaceState = .closed
            @unknown default:
                viewModel.immersiveSpaceState = .closed
            }
        case .inTransition:
            break
        }
    }
}
#endif

#Preview {
    ControlPanelView()
        .environment(UntangleViewModel())
}
