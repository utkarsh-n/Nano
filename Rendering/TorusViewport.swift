import SwiftUI
import SpriteKit
import UIKit

/// Ephemeral feedback for a real intervention; never enters the deterministic world model.
struct TorusVisualCue: Equatable {
    enum Kind: Equatable { case stardust, pulse, warmth, flow, bonds }

    var id: UUID
    var kind: Kind
    var worldID: String
    var particleIDs: Set<Int>?
    var position: Vector2?
    let issuedAt: TimeInterval

    init(id: UUID = UUID(), kind: Kind, worldID: String,
         particleIDs: Set<Int>? = nil, position: Vector2? = nil) {
        self.id = id
        self.kind = kind
        self.worldID = worldID
        self.particleIDs = particleIDs
        self.position = position
        self.issuedAt = ProcessInfo.processInfo.systemUptime
    }
}

/// A live simulation surface. The surrounding controls deliberately remain SwiftUI.
@MainActor
struct TorusViewport: UIViewRepresentable {
    var world: TorusWorld
    var showFields: Bool
    var showTrails: Bool
    var selectedParticleID: Int?
    var onSelectParticle: ((Int) -> Void)?
    var isRunning: Bool
    var visualCue: TorusVisualCue?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        world: TorusWorld,
        showFields: Bool = false,
        showTrails: Bool = true,
        selectedParticleID: Int? = nil,
        onSelectParticle: ((Int) -> Void)? = nil,
        isRunning: Bool = true,
        visualCue: TorusVisualCue? = nil
    ) {
        self.world = world
        self.showFields = showFields
        self.showTrails = showTrails
        self.selectedParticleID = selectedParticleID
        self.onSelectParticle = onSelectParticle
        self.isRunning = isRunning
        self.visualCue = visualCue
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SKView {
        let view = TorusSKView(frame: .zero)
        view.backgroundColor = UIColor(red: 0.014, green: 0.021, blue: 0.055, alpha: 1)
        view.isOpaque = true
        view.ignoresSiblingOrder = true
        view.preferredFramesPerSecond = 30
        view.isMultipleTouchEnabled = true

        let scene = context.coordinator.scene
        scene.scaleMode = .resizeFill
        view.presentScene(scene)

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinch(_:)))
        view.addGestureRecognizer(pinch)
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.minimumNumberOfTouches = 2
        view.addGestureRecognizer(pan)
        let reset = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.resetCamera))
        reset.numberOfTapsRequired = 2
        reset.numberOfTouchesRequired = 2
        view.addGestureRecognizer(reset)
        updateUIView(view, context: context)
        return view
    }

    func updateUIView(_ view: SKView, context: Context) {
        let scene = context.coordinator.scene
        scene.onSelectParticle = onSelectParticle
        scene.apply(
            world: world,
            showFields: showFields,
            showTrails: showTrails,
            selectedParticleID: selectedParticleID,
            interpolate: isRunning && !reduceMotion,
            reduceMotion: reduceMotion,
            visualCue: visualCue?.worldID == world.id ? visualCue : nil
        )
        view.preferredFramesPerSecond = isRunning && !reduceMotion ? 30 : 15
        view.accessibilityLabel = "\(world.name) live torus"
        view.accessibilityValue = "\(world.particles.count) particles, \(world.particles.filter(\.isMature).count) at the rim"
        view.accessibilityHint = onSelectParticle == nil
            ? "Pinch to magnify the torus. Use two fingers to pan."
            : "Use Choose particle to inspect or control a particle."
        view.accessibilityTraits = .image
        view.isAccessibilityElement = true
    }

    static func dismantleUIView(_ view: SKView, coordinator: Coordinator) {
        view.presentScene(nil)
    }

    @MainActor
    final class Coordinator: NSObject {
        let scene = TorusScene(size: CGSize(width: 600, height: 360))
        private var initialScale: CGFloat = 1
        private var initialCameraPosition: CGPoint = .zero

        @objc func pinch(_ recognizer: UIPinchGestureRecognizer) {
            guard let camera = scene.camera else { return }
            if recognizer.state == .began { initialScale = camera.xScale }
            let scale = min(1, max(0.38, initialScale / recognizer.scale))
            camera.setScale(scale)
            scene.constrainCamera()
        }

        @objc func pan(_ recognizer: UIPanGestureRecognizer) {
            guard let camera = scene.camera, let view = recognizer.view else { return }
            if recognizer.state == .began { initialCameraPosition = camera.position }
            let movement = recognizer.translation(in: view)
            camera.position = CGPoint(
                x: initialCameraPosition.x - movement.x * camera.xScale,
                y: initialCameraPosition.y + movement.y * camera.yScale
            )
            scene.constrainCamera()
        }

        @objc func resetCamera() { scene.resetCamera() }
    }
}

/// SpriteKit can expose every rendering node as a separate accessibility child.
/// Keep this canvas a single image; the native particle picker supplies accessible controls.
@MainActor
private final class TorusSKView: SKView {
    override func accessibilityElementCount() -> Int { 0 }
    override func accessibilityElement(at index: Int) -> Any? { nil }
    override func index(ofAccessibilityElement element: Any) -> Int { NSNotFound }
}
