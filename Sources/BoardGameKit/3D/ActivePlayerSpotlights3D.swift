import BoardGameKitHost
import SceneKit

@MainActor public class ActivePlayerSpotlights3D : SCNNode {
    
    struct Checkpoint {
        let rotation: Rotation
        let lightIntensity: Double
    }
    
    public static func createSpotLight() -> SCNNode {
        let light = SCNLight()
        light.type = .spot
        light.intensity = 0
        light.spotInnerAngle = 10
        light.spotOuterAngle = 15
        light.color = Color(red: 1, green: 0.9, blue: 0.5, alpha: 1)
        light.categoryBitMask = 1 << 1
        
        let node = SCNNode()
        node.light = light
        node.simdPosition = Vector3(x: 0, y: 1, z: 0)
        return node
    }
    
    private let players: [UUID: Vector3]
    private var activeLights = RecordedDictionary<UUID, SCNNode>()
    private var inactiveLights: RecordedArray<SCNNode>
    private var lightCheckpoints = RecordedDictionary<SCNNode, Checkpoint>()
    
    public init<PlayerNode: GamePlayerNode3D>(players: [PlayerNode], lights: [SCNNode]) {
        self.players = Dictionary(uniqueKeysWithValues: players.map({ ($0.id, $0.simdWorldPosition) }))
        self.inactiveLights = RecordedArray(lights)
        super.init()
        for light in lights {
            addChildNode(light)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func update(states: [GameManager.EventGroup.PlayerState]?) {
        guard let states = states else {
            return
        }
        for state in states.filter({ $0.state != nil }) {
            let player = state.id
            if activeLights[player] == nil {
                let light: SCNNode
                if let otherPlayer = states.first(where: { $0.state == nil && activeLights[$0.id] != nil })?.id {
                    light = activeLights[otherPlayer]!
                    activeLights[otherPlayer] = nil
                } else if !inactiveLights.isEmpty {
                    light = inactiveLights.removeFirst()
                } else {
                    fatalError("There are not enough spotlights.")
                }
                activeLights[player] = light
                updateLight(light, newCheckpoint: Checkpoint(rotation: Rotation(lookingAnyRollFrom: light.simdPosition, to: players[player]!), lightIntensity: 6000))
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
    
    private func updateLight(_ light: SCNNode, newCheckpoint: Checkpoint?) {
        let timeline = GameSceneContext.current.timeline
        let oldCheckpoint = if let newCheckpoint = newCheckpoint {
            lightCheckpoints.updateValue(newCheckpoint, forKey: light)
        } else {
            lightCheckpoints.removeValue(forKey: light)
        }
        timeline.addAnimation(TimelineAnimation(id: "ActivePlayerSpotlights.updateLight", subject: light, startTime: timeline.currentTime + timeline.timeOffset, duration: 0.5, progress: { t in
            let t = MoveAnimation.TimingMode.easeInEaseOut.apply(t: t)
            light.simdOrientation = MoveAnimation.Rotation.linear.apply(start: oldCheckpoint?.rotation ?? Rotation(lookingAnyRollFrom: light.simdPosition, to: .zero), end: newCheckpoint?.rotation ?? Rotation(lookingAnyRollFrom: light.simdPosition, to: .zero), t: t)
            light.light!.intensity = simd_mix(oldCheckpoint?.lightIntensity ?? 0, newCheckpoint?.lightIntensity ?? 0, t)
        }))
    }
    
}
