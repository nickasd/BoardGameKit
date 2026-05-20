import BoardGameKitHost
import SpriteKit

@MainActor public class ActivePlayerSpotlights2D {
    
    struct Checkpoint {
        let player: UUID
        let alpha: Double
    }
    
    public static func createSpotlight() -> SKNode {
        let circle = SKShapeNode(rectOf: CGSize(width: 94, height: 94), cornerRadius: 47)
        circle.lineWidth = 0
        circle.fillColor = Color(red: 1, green: 0.9, blue: 0.5, alpha: 1)
        let effect = SKEffectNode()
        effect.shouldRasterize = true
        effect.shouldEnableEffects = true
        let filter = CIFilter.boxBlur()
        filter.radius = 60
        effect.filter = filter
        effect.alpha = 0
        effect.zPosition = -1
        effect.addChild(circle)
        return effect
    }
    
    private let players: [UUID: PlayerOverlay]
    private var activeLights = RecordedDictionary<UUID, SKNode>()
    private var inactiveLights: RecordedArray<SKNode>
    private var lightCheckpoints = RecordedDictionary<SKNode, Checkpoint>()
    
    public init<PlayerNode: GamePlayerNode3D>(players: [PlayerNode], lights: [SKNode]) {
        self.players = Dictionary(uniqueKeysWithValues: players.map({ ($0.id, $0.overlay!) }))
        self.inactiveLights = RecordedArray(lights)
    }
    
    public func update(states: [GameManager.EventGroup.PlayerState]?) {
        guard let states = states else {
            return
        }
        for state in states.filter({ $0.state != nil }) {
            let player = state.id
            if activeLights[player] == nil {
                let light: SKNode
                if let otherPlayer = states.first(where: { $0.state == nil && activeLights[$0.id] != nil })?.id {
                    light = activeLights[otherPlayer]!
                    activeLights[otherPlayer] = nil
                } else if !inactiveLights.isEmpty {
                    light = inactiveLights.removeFirst()
                } else {
                    fatalError("There are not enough spotlights.")
                }
                activeLights[player] = light
                updateLight(light, newCheckpoint: Checkpoint(player: player, alpha: 1))
            }
        }
        for state in states.filter({ $0.state == nil }) {
            let player = state.id
            if let light = activeLights[player] {
                updateLight(light, newCheckpoint: nil)
                activeLights[player] = nil
                inactiveLights.append(light)
            }
        }
    }
    
    private func updateLight(_ light: SKNode, newCheckpoint: Checkpoint?) {
        let timeline = GameSceneContext.current.timeline
        let oldCheckpoint = if let newCheckpoint = newCheckpoint {
            lightCheckpoints.updateValue(newCheckpoint, forKey: light)
        } else {
            lightCheckpoints.removeValue(forKey: light)
        }
        timeline.addAnimation(TimelineAnimation(id: "ActivePlayerSpotlights.updateLight", subject: light, startTime: timeline.currentTime + timeline.timeOffset, duration: 0.5, enter: { [self] direction in
            if light.parent == nil {
                switch direction {
                case .forward:
                    if let player = newCheckpoint?.player {
                        players[player]!.parent!.addChild(light)
                    }
                case .backward:
                    if let player = oldCheckpoint?.player {
                        players[player]!.parent!.addChild(light)
                    }
                }
            }
        }, progress: { [self] t in
            let t = MoveAnimation.TimingMode.easeInEaseOut.apply(t: t)
            light.alpha = simd_mix(oldCheckpoint?.alpha ?? 0, newCheckpoint?.alpha ?? 0, t)
            let oldPosition = position(of: light, for: (oldCheckpoint ?? newCheckpoint)!.player)
            let newPosition = position(of: light, for: (newCheckpoint ?? oldCheckpoint)!.player)
            light.position = mix(oldPosition, newPosition, t: t)
        }, exit: { direction in
            switch direction {
            case .forward:
                if newCheckpoint == nil {
                    light.removeFromParent()
                }
            case .backward:
                if oldCheckpoint == nil {
                    light.removeFromParent()
                }
            }
        }))
    }
    
    private func position(of light: SKNode, for player: UUID) -> CGPoint {
        return players[player]!.mainContent.convert(players[player]!.icon.position, to: light.parent!)
    }
    
}

func mix(_ x: CGPoint, _ y: CGPoint, t: Double) -> CGPoint {
    return CGPoint(x: simd_mix(x.x, y.x, t), y: simd_mix(x.y, y.y, t))
}
