import SpriteKit
import UIKit

/// Renders model snapshots; SpriteKit owns no gameplay or independent particle population.
@MainActor
final class TorusScene: SKScene {
    var onSelectParticle: ((Int) -> Void)?

    private let stage = SKSpriteNode(imageNamed: "TorusStage")
    private let cameraNode = SKCameraNode()
    private let dustLayer = SKNode()
    private let trailLayer = SKNode()
    private let bondLayer = SKNode()
    private let fieldLayer = SKNode()
    private let particleLayer = SKNode()
    private let selection = SKShapeNode()
    private let deadZone = SKShapeNode()
    private let cueLayer = SKNode()
    private var particleNodes: [Int: NanoParticleNode] = [:]
    private var dustNodes: [Int: SKShapeNode] = [:]
    private var bondNodes: [Int: SKShapeNode] = [:]
    private var snapshot: TorusWorld?
    private var fieldsVisible = false
    private var trailsVisible = true
    private var selectedID: Int?
    private var interpolates = true
    private var lastFrameTime: TimeInterval = 0
    private var stageFrame: CGRect = .zero
    private var configured = false
    private var projectionRadius = 1.0
    private var cueElements: [CueElement] = []
    private var cueAge: TimeInterval = 0
    private var cueDuration: TimeInterval = 0.85
    private var cueReducedMotion = false
    private var activeCue: TorusVisualCue?
    private var consumedCueIDs: Set<UUID> = []

    override init(size: CGSize) {
        super.init(size: size)
        configure()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        configure()
    }

    private func configure() {
        guard !configured else { return }
        configured = true
        backgroundColor = UIColor(red: 0.014, green: 0.021, blue: 0.055, alpha: 1)
        stage.zPosition = 0
        stage.texture?.filteringMode = .linear
        addChild(stage)
        dustLayer.zPosition = 3
        trailLayer.zPosition = 5
        bondLayer.zPosition = 7
        fieldLayer.zPosition = 8
        particleLayer.zPosition = 10
        [dustLayer, trailLayer, bondLayer, fieldLayer, particleLayer].forEach(addChild)

        selection.strokeColor = UIColor.white.withAlphaComponent(0.96)
        selection.fillColor = .clear
        selection.lineWidth = 1.8
        selection.glowWidth = 2.5
        selection.zPosition = 200
        selection.isHidden = true
        addChild(selection)
        cueLayer.zPosition = 180
        addChild(cueLayer)

        deadZone.fillColor = UIColor(red: 0.11, green: 0.06, blue: 0.18, alpha: 0.2)
        deadZone.strokeColor = UIColor(red: 0.66, green: 0.57, blue: 0.85, alpha: 0.55)
        deadZone.lineWidth = 1
        fieldLayer.addChild(deadZone)
        addChild(cameraNode)
        camera = cameraNode
        layoutStage()
        resetCamera()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard configured else { return }
        let existingCue = activeCue
        let existingAge = cueAge
        layoutStage()
        resetCamera()
        clearCue()
        if let snapshot {
            render(snapshot, forcePosition: true)
            if let existingCue, existingAge < cueDuration {
                showCue(existingCue, world: snapshot, reduceMotion: cueReducedMotion)
                cueAge = existingAge
                updateCue(elapsed: 0)
            }
        }
    }

    func apply(
        world: TorusWorld,
        showFields: Bool,
        showTrails: Bool,
        selectedParticleID: Int?,
        interpolate: Bool,
        reduceMotion: Bool = false,
        visualCue: TorusVisualCue? = nil
    ) {
        let changedWorld = snapshot?.id != world.id
        let resetTimeline = snapshot.map { $0.id == world.id && world.tick < $0.tick } ?? false
        if changedWorld || resetTimeline {
            clearCue()
            particleNodes.values.forEach { $0.removeFromParent(); $0.trail.removeFromParent() }
            particleNodes.removeAll(keepingCapacity: true)
            dustLayer.removeAllChildren()
            dustNodes.removeAll(keepingCapacity: true)
            bondLayer.removeAllChildren()
            bondNodes.removeAll(keepingCapacity: true)
            resetCamera()
        }
        snapshot = world
        fieldsVisible = showFields
        trailsVisible = showTrails
        selectedID = selectedParticleID
        interpolates = interpolate
        fieldLayer.isHidden = !showFields
        trailLayer.isHidden = !showTrails
        render(world, forcePosition: changedWorld || resetTimeline || !interpolate)
        if let visualCue, visualCue.worldID == world.id,
           !consumedCueIDs.contains(visualCue.id) {
            consumedCueIDs.insert(visualCue.id)
            // A newly mounted viewport must not replay an old intervention from the store.
            let age = max(0, ProcessInfo.processInfo.systemUptime - visualCue.issuedAt)
            let duration: TimeInterval = reduceMotion ? 0.65 : 0.95
            if age < duration {
                showCue(visualCue, world: world, reduceMotion: reduceMotion)
                cueAge = age
                updateCue(elapsed: 0)
            }
        }
    }

    private func layoutStage() {
        // Preserve the generated vessel's aspect ratio so the live projection stays registered.
        let imageSize = stage.texture?.size() ?? CGSize(width: 1672, height: 941)
        let scale = min(size.width / imageSize.width, size.height / imageSize.height)
        let rendered = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        stage.size = rendered
        stage.position = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        stageFrame = CGRect(x: (size.width - rendered.width) * 0.5,
                            y: (size.height - rendered.height) * 0.5,
                            width: rendered.width, height: rendered.height)
    }

    /// The physical annulus has an inner radius of .34. The pictured glass is thicker in
    /// perspective, so interpolate its inside and outside ellipses without filling the hole.
    private func project(_ position: Vector2) -> CGPoint {
        let x = position.x / projectionRadius
        let y = position.y / projectionRadius
        let radius = max(0.0001, hypot(x, y))
        let annulus = min(1.08, max(0, (radius - 0.34) / 0.66))
        let horizontalRadius = stageFrame.width * (0.279 + annulus * 0.173)
        let verticalRadius = stageFrame.height * (0.177 + annulus * 0.191)
        return CGPoint(
            x: stageFrame.midX + CGFloat(x / radius) * horizontalRadius,
            y: stageFrame.minY + stageFrame.height * 0.508 + CGFloat(y / radius) * verticalRadius
        )
    }

    private func render(_ world: TorusWorld, forcePosition: Bool) {
        projectionRadius = max(0.01, world.radius)
        let liveIDs = Set(world.particles.map(\.id))
        for id in particleNodes.keys.filter({ !liveIDs.contains($0) }) {
            particleNodes[id]?.trail.removeFromParent()
            particleNodes.removeValue(forKey: id)?.removeFromParent()
        }

        let pixelScale = stageFrame.width / 600
        let matureCount = world.particles.filter(\.isMature).count
        let rimDensityScale = min(1, sqrt(32.0 / Double(max(1, matureCount))))
        for particle in world.particles {
            let node: NanoParticleNode
            let isNew: Bool
            if let existing = particleNodes[particle.id] {
                node = existing
                isNew = false
            } else {
                node = NanoParticleNode()
                particleNodes[particle.id] = node
                particleLayer.addChild(node)
                trailLayer.addChild(node.trail)
                isNew = true
            }
            let point = project(particle.position)
            let depth = CGFloat(min(1, max(0, (particle.position.y / projectionRadius + 1) * 0.5)))
            let diameter = (particle.isMature ? 34.0 * rimDensityScale : 34.0 + particle.coherence * 8) * Double(pixelScale)
            node.configure(particle: particle, diameter: CGFloat(diameter) * (1.11 - depth * 0.27), showField: fieldsVisible)
            node.targetPosition = point
            node.zPosition = 100 - depth * 50
            if forcePosition || isNew { node.position = point }
            if trailsVisible && !particle.isMature {
                let path = CGMutablePath()
                for (index, sample) in particle.trail.enumerated() {
                    let point = project(sample)
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                path.addLine(to: point)
                node.trail.path = path
                node.trail.lineWidth = max(0.5, 0.75 * pixelScale)
                node.trail.alpha = CGFloat(0.25 + particle.energy * 0.35)
            } else {
                node.trail.path = nil
            }
        }
        renderDust(world, scale: pixelScale)
        renderBonds(world, scale: pixelScale)
        renderDeadZone(world)
        updateSelection()
    }

    private func renderDust(_ world: TorusWorld, scale: CGFloat) {
        let liveIDs = Set(world.dust.map(\.id))
        for id in dustNodes.keys.filter({ !liveIDs.contains($0) }) {
            dustNodes.removeValue(forKey: id)?.removeFromParent()
        }
        for deposit in world.dust {
            let node: SKShapeNode
            if let existing = dustNodes[deposit.id] { node = existing }
            else {
                node = SKShapeNode(circleOfRadius: 1)
                node.fillColor = UIColor(red: 1, green: 0.8, blue: 0.4, alpha: 1)
                node.strokeColor = UIColor(red: 1, green: 0.95, blue: 0.69, alpha: 0.75)
                node.lineWidth = 0.35
                node.glowWidth = 1.5
                dustNodes[deposit.id] = node
                dustLayer.addChild(node)
            }
            node.position = project(deposit.position)
            node.setScale(max(0.7, min(2.8, CGFloat(sqrt(max(0, deposit.amount))) * 1.5)) * scale)
            node.alpha = 0.78
        }
    }

    private func renderBonds(_ world: TorusWorld, scale: CGFloat) {
        let liveIDs = Set(world.bonds.map(\.id))
        let particles = Dictionary(uniqueKeysWithValues: world.particles.map { ($0.id, $0) })
        for id in bondNodes.keys.filter({ !liveIDs.contains($0) }) {
            bondNodes.removeValue(forKey: id)?.removeFromParent()
        }
        for bond in world.bonds {
            guard let a = particles[bond.a], let b = particles[bond.b] else { continue }
            let node: SKShapeNode
            if let existing = bondNodes[bond.id] { node = existing }
            else {
                node = SKShapeNode()
                node.fillColor = .clear
                node.strokeColor = UIColor(red: 0.82, green: 0.61, blue: 1, alpha: 1)
                node.blendMode = .add
                node.glowWidth = 2.5
                bondNodes[bond.id] = node
                bondLayer.addChild(node)
            }
            let start = project(a.position)
            let end = project(b.position)
            let path = CGMutablePath()
            path.move(to: start)
            let distance = hypot(end.x - start.x, end.y - start.y)
            path.addQuadCurve(to: end, control: CGPoint(x: (start.x + end.x) * 0.5,
                                                        y: (start.y + end.y) * 0.5 + min(10 * scale, distance * 0.12)))
            node.path = path
            node.lineWidth = max(0.75, 1.3 * scale)
            node.alpha = CGFloat(max(0.25, min(0.85, 0.8 - bond.tension * 0.25)))
        }
    }

    private func renderDeadZone(_ world: TorusWorld) {
        guard fieldsVisible else { return }
        let center = project(world.deadZoneCenter)
        let radius = CGFloat(world.deadZoneRadius / projectionRadius) * stageFrame.width * 0.2
        deadZone.path = CGPath(ellipseIn: CGRect(x: -radius, y: -radius * 0.55, width: radius * 2, height: radius * 1.1), transform: nil)
        deadZone.position = center
    }

    private func updateSelection() {
        guard let selectedID, let node = particleNodes[selectedID] else {
            selection.isHidden = true
            return
        }
        selection.isHidden = false
        let radius = node.diameter * 0.64
        selection.path = CGPath(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2), transform: nil)
        selection.position = node.position
    }

    private struct CueElement {
        var node: SKShapeNode
        var particleID: Int?
        var dustID: Int?
        var bondID: Int?
        var position: Vector2?
        var offset: CGPoint = .zero
        var expansion: CGFloat = 0
        var turn: CGFloat = 0
        var rise: CGFloat = 0
    }

    private func clearCue() {
        cueLayer.removeAllChildren()
        cueElements.removeAll(keepingCapacity: true)
        cueAge = 0
        activeCue = nil
    }

    private func showCue(_ cue: TorusVisualCue, world: TorusWorld, reduceMotion: Bool) {
        clearCue()
        activeCue = cue
        cueReducedMotion = reduceMotion
        cueDuration = reduceMotion ? 0.65 : 0.95
        let scale = stageFrame.width / 600
        let gold = UIColor(red: 1, green: 0.78, blue: 0.34, alpha: 1)
        let cyan = UIColor(red: 0.42, green: 0.92, blue: 1, alpha: 1)

        switch cue.kind {
        case .stardust:
            if let position = cue.position {
                // Feedback marks the actual seed command location, never an unrelated deposit.
                for index in 0..<7 {
                    let angle = CGFloat(index) * .pi * 2 / 7
                    let offset = CGPoint(x: cos(angle) * 7 * scale, y: sin(angle) * 4 * scale)
                    let node = stardustFleck(color: gold, scale: scale)
                    addCue(CueElement(node: node, position: position, offset: offset,
                                      expansion: 0.4, rise: 7 * scale))
                }
            } else {
                // Without a target location, acknowledge existing material only.
                for deposit in world.dust.prefix(16) {
                    let node = stardustFleck(color: gold, scale: scale)
                    addCue(CueElement(node: node, dustID: deposit.id, expansion: 0.4, rise: 7 * scale))
                }
            }

        case .pulse, .warmth:
            let warmth = cue.kind == .warmth
            var count = 0
            for particle in world.particles {
                if !warmth {
                    if let ids = cue.particleIDs {
                        guard ids.contains(particle.id) else { continue }
                    } else {
                        guard !particle.isMature else { continue }
                    }
                }
                guard count < 20, let particleNode = particleNodes[particle.id] else { continue }
                count += 1
                let color = warmth || particle.polarity > 0 ? gold : cyan
                let node = cueNode(color: color, scale: scale)
                let radius = particleNode.diameter * (warmth ? 0.53 : 0.59)
                node.path = CGPath(ellipseIn: CGRect(x: -radius, y: -radius,
                                                   width: radius * 2, height: radius * 2), transform: nil)
                node.fillColor = color.withAlphaComponent(warmth ? 0.13 : 0.055)
                node.lineWidth = warmth ? max(1, 3 * scale) : max(0.8, 1.3 * scale)
                node.glowWidth = warmth ? 6 * scale : 3 * scale
                addCue(CueElement(node: node, particleID: particle.id, expansion: warmth ? 0.08 : 0.60))
            }

        case .flow:
            var count = 0
            for particle in world.particles where !particle.isMature {
                guard count < 12, let particleNode = particleNodes[particle.id] else { continue }
                count += 1
                let node = cueNode(color: cyan, scale: scale)
                let radius = particleNode.diameter * 0.7
                let path = CGMutablePath()
                path.addArc(center: .zero, radius: radius, startAngle: -.pi * 0.25,
                            endAngle: .pi * 1.05, clockwise: false)
                let tip = CGPoint(x: cos(.pi * 1.05) * radius, y: sin(.pi * 1.05) * radius)
                path.addLine(to: CGPoint(x: tip.x + radius * 0.22, y: tip.y + radius * 0.12))
                node.path = path
                addCue(CueElement(node: node, particleID: particle.id, turn: 0.75))
            }

        case .bonds:
            // Only existing bonds light up; an empty network stays visually empty.
            for bond in world.bonds.prefix(24) {
                guard let actualBond = bondNodes[bond.id], let path = actualBond.path else { continue }
                let node = cueNode(color: UIColor(red: 0.89, green: 0.63, blue: 1, alpha: 1), scale: scale)
                node.path = path
                node.lineWidth = max(1, 2.2 * scale)
                node.glowWidth = 5 * scale
                addCue(CueElement(node: node, bondID: bond.id))
            }
        }
        guard !cueElements.isEmpty else { clearCue(); return }
        updateCue(elapsed: 0)
    }

    private func stardustFleck(color: UIColor, scale: CGFloat) -> SKShapeNode {
        let node = cueNode(color: color, scale: scale)
        let radius = max(1, 3.0 * scale)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -radius, y: 0))
        path.addLine(to: CGPoint(x: radius, y: 0))
        path.move(to: CGPoint(x: 0, y: -radius))
        path.addLine(to: CGPoint(x: 0, y: radius))
        node.path = path
        return node
    }

    private func cueNode(color: UIColor, scale: CGFloat) -> SKShapeNode {
        let node = SKShapeNode()
        node.strokeColor = color
        node.fillColor = .clear
        node.lineWidth = max(0.7, 1.2 * scale)
        node.glowWidth = 3 * scale
        node.blendMode = .add
        return node
    }

    private func addCue(_ element: CueElement) {
        cueElements.append(element)
        cueLayer.addChild(element.node)
    }

    private func updateCue(elapsed: TimeInterval) {
        guard !cueElements.isEmpty else { return }
        cueAge += elapsed
        if let activeCue {
            cueAge = max(cueAge, ProcessInfo.processInfo.systemUptime - activeCue.issuedAt)
        }
        guard cueAge < cueDuration else { clearCue(); return }
        let phase = CGFloat(cueAge / cueDuration)
        cueLayer.alpha = pow(1 - phase, 1.25)
        for element in cueElements {
            if let id = element.particleID {
                guard let actual = particleNodes[id] else { element.node.isHidden = true; continue }
                element.node.position = actual.position
            } else if let id = element.dustID {
                guard let actual = dustNodes[id] else { element.node.isHidden = true; continue }
                element.node.position = actual.position
            } else if let id = element.bondID {
                guard let actual = bondNodes[id] else { element.node.isHidden = true; continue }
                element.node.path = actual.path
            } else if let position = element.position {
                element.node.position = project(position)
            }
            element.node.position.x += element.offset.x
            element.node.position.y += element.offset.y
            if !cueReducedMotion {
                element.node.setScale(1 + element.expansion * phase)
                element.node.zRotation = element.turn * phase
                element.node.position.y += element.rise * phase
            }
        }
    }

    override func update(_ currentTime: TimeInterval) {
        let elapsed = lastFrameTime == 0 ? 1.0 / 30 : min(0.1, currentTime - lastFrameTime)
        lastFrameTime = currentTime
        // Feedback stays responsive when the deterministic simulation is paused.
        updateCue(elapsed: elapsed)
        guard interpolates else { return }
        let blend = CGFloat(1 - exp(-elapsed * 22))
        for node in particleNodes.values {
            node.position.x += (node.targetPosition.x - node.position.x) * blend
            node.position.y += (node.targetPosition.y - node.position.y) * blend
        }
        if !selection.isHidden { updateSelection() }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard touches.count == 1, let touch = touches.first, touch.tapCount == 1, onSelectParticle != nil else { return }
        let location = touch.location(in: self)
        let candidate = particleNodes.min { left, right in
            hypot(left.value.position.x - location.x, left.value.position.y - location.y)
            < hypot(right.value.position.x - location.x, right.value.position.y - location.y)
        }
        guard let (id, node) = candidate else { return }
        let radius = max(node.diameter * 0.68, 20 * cameraNode.xScale)
        guard hypot(node.position.x - location.x, node.position.y - location.y) <= radius else { return }
        onSelectParticle?(id)
    }

    func resetCamera() {
        cameraNode.setScale(1)
        cameraNode.position = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
    }

    func constrainCamera() {
        let halfWidth = size.width * cameraNode.xScale * 0.5
        let halfHeight = size.height * cameraNode.yScale * 0.5
        cameraNode.position.x = min(size.width - halfWidth, max(halfWidth, cameraNode.position.x))
        cameraNode.position.y = min(size.height - halfHeight, max(halfHeight, cameraNode.position.y))
    }
}

@MainActor
private final class NanoParticleNode: SKNode {
    let sprite = SKSpriteNode()
    let halo = SKShapeNode()
    let field = SKShapeNode()
    let trail = SKShapeNode()
    private let shadow = SKShapeNode()
    private var textureName = ""
    var targetPosition = CGPoint.zero
    var diameter: CGFloat = 24

    override init() {
        super.init()
        shadow.fillColor = UIColor(red: 0.01, green: 0.02, blue: 0.10, alpha: 0.6)
        shadow.strokeColor = .clear
        shadow.zPosition = -3
        halo.fillColor = .clear
        halo.lineWidth = 0.7
        halo.glowWidth = 2
        halo.blendMode = .add
        halo.zPosition = -1
        field.fillColor = .clear
        field.lineWidth = 0.5
        field.zPosition = -2
        trail.fillColor = .clear
        trail.glowWidth = 1
        trail.blendMode = .add
        sprite.zPosition = 1
        addChild(shadow)
        addChild(field)
        addChild(halo)
        addChild(sprite)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(particle: TorusParticle, diameter: CGFloat, showField: Bool) {
        self.diameter = diameter
        let name: String
        if particle.isMature || particle.polarity == 0 { name = "NanoPearl" }
        else if particle.polarity > 0 { name = "NanoGold" }
        else { name = "NanoCrystal" }
        if textureName != name {
            textureName = name
            sprite.texture = SKTexture(imageNamed: name)
            sprite.texture?.filteringMode = .linear
        }
        // Sprite artwork includes its own lighting; gameplay fields are separate readable layers.
        sprite.size = CGSize(width: diameter, height: diameter)
        let color: UIColor
        if particle.isMature { color = UIColor(red: 1, green: 0.9, blue: 0.65, alpha: 1) }
        else if particle.polarity > 0 { color = UIColor(red: 1, green: 0.66, blue: 0.24, alpha: 1) }
        else if particle.polarity < 0 { color = UIColor(red: 0.35, green: 0.74, blue: 1, alpha: 1) }
        else { color = UIColor(red: 0.84, green: 0.77, blue: 1, alpha: 1) }
        halo.strokeColor = color
        halo.alpha = CGFloat(0.25 + min(1, max(0, particle.energy)) * 0.5)
        halo.path = CGPath(ellipseIn: CGRect(x: -diameter * 0.40, y: -diameter * 0.40,
                                           width: diameter * 0.80, height: diameter * 0.80), transform: nil)
        shadow.path = CGPath(ellipseIn: CGRect(x: -diameter * 0.33, y: -diameter * 0.48,
                                             width: diameter * 0.66, height: diameter * 0.24), transform: nil)
        field.isHidden = !showField
        field.strokeColor = color.withAlphaComponent(0.36)
        let fieldRadius = diameter * CGFloat(0.72 + particle.energy * 0.24)
        field.path = CGPath(ellipseIn: CGRect(x: -fieldRadius, y: -fieldRadius * 0.64,
                                            width: fieldRadius * 2, height: fieldRadius * 1.28), transform: nil)
        trail.strokeColor = color
    }
}
