import SwiftUI
import RealityKit

struct ContentView: View {
    @State private var world = FruitWorld()

    // Estado dos gestos
    @State private var appleDragStartY: Float?
    @State private var appleOpeningAtStart: Float = 0
    @State private var seedGrabOffset: SIMD3<Float>?
    @State private var magnifyStart: Float?

    var body: some View {
        RealityView { content in
            content.add(world.root)
        }
        // Arrastar: puxa o cabinho da maçã OU move uma semente da romã.
        .gesture(
            DragGesture()
                .targetedToAnyEntity()
                .onChanged { value in
                    let entity = value.entity

                    if world.selected == .apple, entity === world.apple.handle {
                        let y = value.convert(value.location3D, from: .local, to: .scene).y
                        if appleDragStartY == nil {
                            appleDragStartY = y
                            appleOpeningAtStart = world.apple.opening
                        }
                        let delta = y - (appleDragStartY ?? y)
                        world.apple.setOpening(appleOpeningAtStart + delta / world.apple.shape.maxLift)

                    } else if world.pomegranate.isFreeSeed(entity), let parent = entity.parent {
                        let p = value.convert(value.location3D, from: .local, to: parent)
                        if seedGrabOffset == nil {
                            seedGrabOffset = world.pomegranate.home(of: entity) - p
                        }
                        world.pomegranate.moveSeed(entity, to: p + (seedGrabOffset ?? .zero))
                    }
                }
                .onEnded { value in
                    appleDragStartY = nil
                    if seedGrabOffset != nil {
                        world.pomegranate.endSeedDrag(value.entity)
                    }
                    seedGrabOffset = nil
                }
        )
        // Tocar: escolhe uma fruta ou coleta uma minhoca.
        .simultaneousGesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in world.handleTap(on: value.entity) }
        )
        // Duas mãos afastando: abre a romã.
        .simultaneousGesture(
            MagnifyGesture()
                .targetedToAnyEntity()
                .onChanged { value in
                    guard world.selected == .pomegranate,
                          world.fruitKind(of: value.entity) == .pomegranate else { return }
                    if magnifyStart == nil {
                        magnifyStart = world.pomegranate.opening
                    }
                    let m = Float(value.magnification)
                    world.pomegranate.setOpening((magnifyStart ?? 0) + (m - 1) / 0.6)
                }
                .onEnded { _ in magnifyStart = nil }
        )
        .ornament(attachmentAnchor: .scene(.bottom)) {
            HStack(spacing: 20) {
                switch world.selected {
                case .none:
                    Text("Toque em uma fruta")
                        .font(.headline)

                case .some(.apple):
                    Text("Minhocas: \(world.apple.collected)/\(world.apple.totalWorms)")
                        .font(.headline)
                    Button("Recomeçar") { world.apple.reset() }
                    Button("Voltar") { world.back() }

                case .some(.pomegranate):
                    Text(world.pomegranate.burst
                         ? "Toque e arraste as sementes"
                         : "Abra com as duas mãos")
                        .font(.headline)
                    Button("Recomeçar") { world.pomegranate.reset() }
                    Button("Voltar") { world.back() }
                }
            }
            .padding()
            .glassBackgroundEffect()
        }
    }
}

