import BoardGameKitHost
import SceneKit
import SpriteKit

public class MainScene: Scene3D {
    
    private let cameraDefault = Transform(position: Vector3(x: 0, y: 1, z: 0), rotation: Rotation(x: -.pi / 2))
    private let cameraSampleGame = (angle: (0.5 + 1.0 / 8) * Float.pi, radius: Float(0.5), height: Float(0.5), lookAt: Vector3(x: 0, y: 0.1, z: 0))
    private var sampleGame: (scene: any GameScene3D, context: GameSceneContext)?
    
    public required override init() {
        super.init()
        if Scene2D.current is LaunchScene {
            Scene3D.mainCamera.myTransform = cameraDefault
        }
        Scene2D.current.transition(to: ClientConfiguration.shared.scenes.mainMenu.init())
        Task {
            do {
                try await addSampleGame()
                if Scene3D.current != self {
                    return
                }
                if sampleGame == nil {
                    moveCamera(to: cameraDefault)
                } else {
                    flyCameraAroundSampleGame()
                }
            } catch {
                showError(error)
            }
        }
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func transition(to scene: Scene3D) {
        sampleGame?.scene.close()
        sampleGame?.scene.releaseCheckpoints(node: self)
        sampleGame?.context.timeline.removeAllActions()
        super.transition(to: scene)
    }
    
    private func addSampleGame() async throws {
        guard let (savedGame, eventGroups) = try parseRandomSampleGame() else {
            return
        }
        let gameSceneContext = GameSceneContext(gameContext: GameContext(undoManager: nil))
        let scene = gameSceneContext.makeCurrent {
            switch ClientConfiguration.shared.scenes.game {
            case .scene3D(let gameScene):
                gameScene.init()
            case .scene2D:
                preconditionFailure()
            }
        }
        sampleGame = (scene, gameSceneContext)
        scene.opacity = 0
        scene.simdScale = Vector3(repeating: ClientConfiguration.shared.sampleGameScale)
        addChildNode(scene)
        try await scene.load(localizedPlayers: savedGame.players.map({ LocalizedPlayer(name: "", gameCharacter: nil, savedPlayer: $0) }), options: savedGame.options)
        scene.runAction(.fadeIn(duration: 1)) { @Sendable in } // Using SCNAction.customAction(duration:action:) causes crash with Swift 6 language mode (FB15570385)
        let timeline = gameSceneContext.timeline
        try gameSceneContext.makeCurrent {
            for eventGroup in eventGroups {
//                Logger.shared.info(eventGroup.map({ RawRequest($0).prettyPrinted }).joined(separator: "\n"))
                timeline.beginUndoGrouping()
                do {
                    try scene.handle(eventGroup: eventGroup)
                } catch {
                    throw HostError(message: "Error during handling of event group \(eventGroup.id)\n\(error.localizedDescription)")
                }
                timeline.endUndoGrouping(startAsyncAnimations: false)
                timeline.seek(to: timeline.duration)
            }
            timeline.seek(to: 0)
        }
//        let start = (time: Date(), seek: [0, timeline.duration].randomElement()!)
//        let speed = Double.random(in: start.seek == 0 ? 0..<2.0 : -2.0..<0)
        let start = (time: Date(), seek: 0.0)
        let speed = 0.33
        scene.runAction(.customAction(duration: 999999) { scene, t in
            Task { @MainActor in
                timeline.seek(to: max(0, min(start.seek - start.time.timeIntervalSinceNow * speed, timeline.duration)))
                if timeline.currentTime == 0 || timeline.currentTime == timeline.duration {
                    scene.removeAction(forKey: "playback")
                }
            }
        }, forKey: "playback") { @Sendable in }
    }
    
    private func parseRandomSampleGame() throws -> (savedGame: SavedGame, eventGroups: [GameManager.EventGroupResponse])? {
        guard let sampleGamesPath = ClientConfiguration.shared.sampleGamesPath else {
            return nil
        }
        let sampleGames = Bundle.main.urls(forResourcesWithExtension: nil, subdirectory: sampleGamesPath)
        let urls = (sampleGames ?? []) + LocalGames.shared.archivedGames()
        #if DEBUG
        for url in urls {
            Logger.shared.info("(Debug mode only) Parsing game at \(url.path)")
            do {
                let savedGame = try RequestCoder.decode(SavedGame.self, from: Data(contentsOf: url))
                let _ = try parseGame(savedGame)
            } catch {
                throw HostError(message: "Error while loading sample game at\n\(url.path)\n\n\(error.localizedDescription)")
            }
        }
        #endif
        guard let url = urls.randomElement() else {
            return nil
        }
        Logger.shared.info("Parsing game at \(url.path)")
        do {
            let savedGame = try RequestCoder.decode(SavedGame.self, from: Data(contentsOf: url))
            let eventGroups = try parseGame(savedGame)
            return (savedGame, eventGroups)
        } catch {
            throw HostError(message: "Error while loading sample game at\n\(url.path)\n\n\(error.localizedDescription)")
        }
    }
    
    private func parseGame(_ savedGame: SavedGame) throws -> [GameManager.EventGroupResponse] {
        var eventGroups = [GameManager.EventGroupResponse]()
        try GameContext(undoManager: nil).makeCurrent {
            let game = try HostConfiguration.shared.game.from(savedGame: savedGame)
            for action in savedGame.actions {
                let context = GameActionContext(action: action, isReplay: true)
                do {
                    try game.handle(context: context)
                } catch {
                    throw HostError(message: "Replay action \(action.id) (\(action.name)) failed. \(error.localizedDescription)")
                }
                eventGroups.append(GameManager.EventGroupResponse(id: action.id, isLiveAction: false, events: context.generatedEvents(for: savedGame.players.map({ $0.id })), playerStateChanges: nil, hasEnded: nil))
            }
            game.close()
        }
        return eventGroups
    }
    
    private func flyCameraAroundSampleGame() {
        let position = Vector3(x: cos(cameraSampleGame.angle) * cameraSampleGame.radius, y: cameraSampleGame.height, z: sin(cameraSampleGame.angle) * cameraSampleGame.radius)
        Scene3D.mainCamera.runAction(.sequence([
            .transform(Transform(position: position, rotation: Rotation(lookingFrom: position, to: cameraSampleGame.lookAt)), duration: 2).withTimingMode(.easeInEaseOut),
            .customAction(duration: 999999, action: { [cameraSampleGame] node, t in // Running SCNAction.custom() with infinite duration causes t parameter to be NaN (FB9464850, fixed in macOS 12 and iOS 15), Using SCNAction.customAction(duration:action:) causes crash with Swift 6 language mode (FB15570385)
                var t = Float(t)
                let duration = Float(60)
                let repetition = Int(floor(t / duration))
                t = t.truncatingRemainder(dividingBy: duration)
                t = simd_smoothstep(0, duration, t)
                let angle = cameraSampleGame.angle + (Float(repetition) + t) * 0.5 * .pi
                t = repetition % 2 == 0 ? t : 1 - t
                let radius = 0.001 + (cameraSampleGame.radius - 0.001) * (1 - t)
                let height = cameraSampleGame.height + t * 0.4
                Scene3D.mainCamera.simdPosition = Vector3(x: cos(angle) * radius, y: height, z: sin(angle) * radius)
                Scene3D.mainCamera.simdOrientation = Rotation(lookingFrom: Scene3D.mainCamera.simdPosition, to: cameraSampleGame.lookAt)
            })
        ]), forKey: "move")
    }
    
}

extension User {
    
    private enum Keys {
        static let userId = "userId"
        static let username = "username"
    }
    
    @MainActor static var savedLocalUser: User {
        let id = UserDefaults.standard.string(forKey: Keys.userId).flatMap({ UUID(uuidString: $0) }) ?? UUID()
        UserDefaults.standard.set(id.uuidString, forKey: Keys.userId)
        return User(id: id, name: NSUserName())
    }

    @MainActor static var savedOnlineUser: User? {
        get {
            if let id = UserDefaults.standard.string(forKey: Keys.userId).flatMap({ UUID(uuidString: $0) }), let name = UserDefaults.standard.string(forKey: Keys.username) {
                User(id: id, name: name)
            } else {
                nil
            }
        }
        set {
            if let newValue = newValue {
                UserDefaults.standard.set(newValue.id.uuidString, forKey: Keys.userId)
                UserDefaults.standard.set(newValue.name, forKey: Keys.username)
            }
        }
    }

}
