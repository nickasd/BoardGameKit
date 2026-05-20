import BoardGameKitHost
import SceneKit
import SpriteKit
import AVFoundation

@MainActor public protocol GameScene3D: SCNNode {
    associatedtype PlayerNode: GamePlayerNode3D
    associatedtype Options: GameOptions
    
    var players: [PlayerNode] { get }
    /// If the local player is the only player on the current device, this property is set only once, otherwise it is alternatively set and unset when switching between the device's local players.
    var localPlayer: PlayerNode? { get set }
    /// The focused player can be changed by tapping the respective player overlay.
    var focusedPlayer: PlayerNode? { get set }
    /// The event handler receives actions from the game scene and is responsible for acting appropriately, e.g. by forwarding game actions to the server.
    var actionHandler: GameSceneActionHandler3D? { get set }
    
    func load(localizedPlayers: [LocalizedPlayer], options: Options) async throws
    func handle(eventGroup: GameManager.EventGroupResponse) throws
    func handle(error: GameManager.GameErrorResponse) throws
    /// Called when a game is closed. Implement this method to release any cyclic references and avoid memory leaks.
    func close()
    /// The overlay can contain buttons and other elements. When the game is disabled, such as when navigating the timeline, the overlay is hidden.
    var overlay: SKNode? { get }
    /// This method is called when the size of the overlay changes.
    func layoutOverlay(in frame: CGRect)
    /// The camera transform used when focusing on the player.
    func cameraTransform(for player: PlayerNode) -> Transform
    
    /**
     This method is called when the private data for the given `player` should be hidden or shown.
     
     At the beginning of a live game, this method is called for each player with `hide` equal to `true`. A usual implementation sets `hideChildren = hide` for all `NodeGroup` objects that contain private data.

     If the local player is the only player on the current device, this method is called with `hide` equal to `false` for the local player. If there are two or more players sharing the current device and the current player changes, this method is called with `hide` equal to `true` with the current local player, followed by a call with `hide` equal to `false` with the new local player.
     */
    func hidePrivateData(_ hide: Bool, for player: PlayerNode)
    
    /**
     This method is called when the actions for the given `player` should be enabled or disabled.
     
     Before the player state changes, this method is called with `enable` equal to `false`, and after the state has changed, this method is called with `enable` equal to `true`.
     
     In a usual implementation, you set the `isEnabled` property of all interactive `ButtonNode` objects to be equal to `enable`. At the same time you also set the `tap` and `drag` properties.
     */
    func enableActions(_ enable: Bool, for player: PlayerNode)
}

@MainActor public protocol GamePlayerNode3D: SCNNode, Identifiable where ID == UUID {
    var id: ID { get }
    var overlay: PlayerOverlay? { get }
}

@MainActor public protocol GameSceneActionHandler3D {
    func sendAction(_ data: any GameAction)
    func startDrag(node: ButtonNode3D)
    func endDrag()
    func moveCamera(to transform: Transform)
    /// Lets the event handler know when the timeline has new async animations to run.
    func runAsyncAnimations()
    func showEndGameRanking(_ ranking: [(player: UUID, text: String)])
}

public class PlayerOverlay: ButtonNode2D {
    
    /// The main content includes the player icon, name and custom view, and its size is used to position the overlay over the respective node in the 3D scene.
    public private(set) var mainContent: SKNode!
    private(set) var icon: PlayerIcon!
    
    public init(localizedPlayer: LocalizedPlayer, customView: SKNode?) {
        super.init()
        mainContent = SKNode()
        addChild(mainContent)
        icon = PlayerIcon(size: 50, name: localizedPlayer.gameCharacter?.icon, borderWidth: 4, borderColor: .clear, shadowColor: .black.withAlphaComponent(0.9))
        icon.position = CGPoint(x: 25, y: 0)
        mainContent.addChild(icon)
        let label = TextNode2D(string: localizedPlayer.name, fontSize: 20, horizontalAlignment: .left, shadowColor: .black.withAlphaComponent(0.9))
        label.position = CGPoint(x: 65, y: icon.position.y - 10)
        mainContent.addChild(label)
        if let customView = customView {
            mainContent.addChild(customView)
            let frame = customView.calculateAccumulatedFrame()
            customView.position = label.position + CGPoint(x: -frame.minX, y: -5 - frame.minY - frame.height / 2)
            label.position.y += 5 + frame.height / 2
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}

extension GameScene3D {
    
    public func load(localizedPlayers: [LocalizedPlayer], options: String?) async throws {
        try await load(localizedPlayers: localizedPlayers, options: options.map({ try RequestCoder.decode(Options.self, from: Data($0.utf8)) }) ?? Options())
    }
    
    /// Positions the first player at `mainPosition` and the other players at `otherPositions`. If `hostPlayer` is not nil, `players` is wrapped so that `hostPlayer` is placed at `mainPosition`.
    public func positionPlayers(_ players: [PlayerNode], mainPosition: PointGenerator.Point, otherPositions: PointGenerator, hostPlayer: UUID?) {
        let players = if let hostPlayer = hostPlayer.flatMap({ players.first(id: $0) }) {
            players.wrapped(first: hostPlayer)
        } else {
            players
        }
        players[0].myTransform = Transform(position: Vector3(x: mainPosition.x, y: 0, z: mainPosition.y))
        for (player, (position, angle)) in zip(players.dropFirst(), otherPositions.generate(count: players.count - 1)) {
            player.myTransform = Transform(position: Vector3(x: position.x, y: 0, z: position.y), rotation: Rotation(y: angle))
        }
    }
    
    public var overlay: SKNode? {
        return nil
    }
    
    public func layoutOverlay(in frame: CGRect) {
        positionPlayerOverlays(for: players, in: frame)
    }
    
    /// Positions the player overlays so that they are on top of the respective player node in the 3D scene. The overlay for `focusedPlayer`, if not nil, is constrained to the bottom window edge, only moving horizontally.
    public func positionPlayerOverlays(for players: [PlayerNode], at projectionOffset: Vector3 = Vector3(x: 0, y: 0.08, z: 0), margin: CGSize = CGSize(width: 25.0, height: 50.0), in frame: CGRect) {
        for player in players {
            guard let overlay = player.overlay else {
                continue
            }
            var point = projectPoint(player.simdWorldPosition + projectionOffset)
            let width = overlay.mainContent.calculateAccumulatedFrame().width
            point.x -= width / 3
            point.x = max(min(point.x, frame.maxX - margin.width - width), frame.minX + margin.width)
            point.y = if player == focusedPlayer {
                frame.minY + margin.height
            } else {
                max(min(point.y, frame.maxY - margin.height), frame.minY + margin.height)
            }
            overlay.position = point
        }
    }
    
    public func projectPoint(_ point: Vector3) -> CGPoint {
        let vector = GameViewController.shared.scnView!.projectPoint(SCNVector3(point)) // SceneKit app seriously hangs when run in fullscreen (FB15737374)
        return GameViewController.shared.scnView!.overlaySKScene!.convertPoint(fromView: CGPoint(x: Double(vector.x), y: Double(vector.y)))
    }
    
    public func cameraTransform(for player: PlayerNode) -> Transform {
        return player.worldTransform(offsetBy: Transform(position: Vector3(x: 0, y: 0.2, z: 0.12), rotation: Rotation(x: -0.7)))
    }
    
    /**
     This method updates each animations in the timeline whose `subject` has a different checkpoint before and after calling `block`.
     
     For example, `block` might change a `NodeGroup.childOrder` property to reorder cards held by a player. This method animates the cards to their new positions and implicitly updates past animations to reflect the changes.
     */
    public func updateAllAnimations(in timeline: Timeline, with block: () -> Void) {
        let subjects = Array(Dictionary(timeline.eventGroups[..<(timeline.eventGroups.firstIndex(where: { timeline.currentTime < $0.startTime }) ?? timeline.eventGroups.endIndex)].flatMap({ $0.animations.filter({ $0.startTime <= timeline.currentTime }) }).map({ ($0.subject, $0) }), uniquingKeysWith: { old, new in new }).values).compactMap({ $0.subject as? GameElementNode })
        let oldTransforms = subjects.map({ $0.checkpoint!.worldTransform })
        block()
        for (subject, oldTransform) in zip(subjects, oldTransforms) {
            let newTransform = subject.checkpoint!.worldTransform
            if newTransform != oldTransform {
                timeline.addEphemeralAnimation(TimelineAnimation(id: "GameScene3D.updateAllAnimations", subject: subject, startTime: timeline.currentTime, duration: 0.3, progress: { t in
                    let t = MoveAnimation.TimingMode.easeOut.apply(t: t)
                    subject.simdWorldPosition = MoveAnimation.Path.linear.apply(start: oldTransform.position, end: newTransform.position, t: t)
                    subject.simdWorldOrientation = MoveAnimation.Rotation.linear.apply(start: oldTransform.rotation, end: newTransform.rotation, t: t)
                }))
            }
        }
        actionHandler?.runAsyncAnimations()
    }
    
    public func releaseCheckpoints(node: SCNNode) {
        if let node = node as? GameElementNode {
            node.$checkpoint._wrappedValue = nil
        }
        for child in node.childNodes {
            releaseCheckpoints(node: child)
        }
    }

}

extension GamePlayerNode3D {
    
    public var overlay: PlayerOverlay? {
        return nil
    }
    
    public func worldTransform(offsetBy offset: Transform) -> Transform {
        return Transform(position: simdWorldPosition + simdWorldOrientation.act(offset.position), rotation: simdWorldOrientation * offset.rotation)
    }
    
}

public enum StandardButtonTitles {
    case pass
    case confirm
    case cancel
    
    public var localizedTitle: String {
        return switch self {
        case .pass:
            NSLocalizedString("game.action.pass", bundle: .boardGameKit, value: "Pass", comment: "")
        case .confirm:
            NSLocalizedString("game.action.confirm", bundle: .boardGameKit, value: "Confirm", comment: "")
        case .cancel:
            NSLocalizedString("game.action.cancel", bundle: .boardGameKit, value: "Cancel", comment: "")
        }
    }
}

/// Creates an animation that fades in the given `node` and fades it out again at the end.
@MainActor public func transientOverlayAnimation(with node: SKNode, in overlay: SKNode, position: CGPoint, timeOffset: TimeInterval = 0, duration: TimeInterval, progress: ((_ t: TimeInterval) -> Void)? = nil) -> TimelineAnimation {
    let timeline = GameSceneContext.current.timeline
    node.position = position
    return TimelineAnimation(id: "transientOverlayAnimation", subject: node, startTime: timeline.currentTime + timeline.timeOffset + timeOffset, duration: duration, enter: { _ in
        overlay.addChild(node)
    }, progress: progress ?? { t in
        if t < 0.2 {
            let t = MoveAnimation.TimingMode.easeOut.apply(t: t / 0.2)
            node.alpha = t
            node.setScale(simd_mix(3, 1, t))
        } else if t < 0.8 {
            node.alpha = 1
        } else {
            let t = MoveAnimation.TimingMode.easeIn.apply(t: (t - 0.8) / 0.2)
            node.alpha = 1 - t
            node.setScale(simd_mix(1, 0, t))
        }
    }, exit: { _ in
        node.removeFromParent()
    })
}
