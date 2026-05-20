import BoardGameKitHost
import SpriteKit

public class GameSceneManager2D: SKNode, GameSceneActionHandler2D, AnyGameSceneManager {
    
    class Player: Identifiable {
        
        let localizedPlayer: LocalizedPlayer
        var status: GameRoom.Status?
        var player: (any GamePlayerNode2D)!
        var overlay: PlayerOverlay?
        @Recorded var isWaiting = true
        
        init(localizedPlayer: LocalizedPlayer, status: GameRoom.Status?) {
            self.localizedPlayer = localizedPlayer
            self.status = status
        }
        
        var id: UUID {
            return localizedPlayer.id
        }
        
    }
    
    private let gameSceneContext = GameSceneContext.current
    public let gameScene: any GameScene2D
    private let players: [Player]
    weak var overlay: GameOverlayScene!
    private var hasEnded: Bool
    private let animationRate = (live: TimeInterval(1), undo: TimeInterval(4))
    private var lastReplayEventGroup: Int?
    private var nextGameplayRate: Double
    private var pendingEventGroups = [GameManager.EventGroupResponse]()
    private var changeLocalPlayer: (button: ButtonNode2D, image: ImageButton2D, label: TextNode2D)?
    
    init(data: GameRoom.StartGameResponse, localizedPlayers: [LocalizedPlayer]) {
        gameScene = switch ClientConfiguration.shared.scenes.game {
        case .scene3D:
            preconditionFailure()
        case .scene2D(let gameScene):
            gameScene.init()
        }
        players = localizedPlayers.map({ Player(localizedPlayer: $0, status: $0.savedPlayer.botStrategy != nil ? nil : .dropped) })
        lastReplayEventGroup = data.lastReplayEventGroup
        hasEnded = data.hasEnded
        nextGameplayRate = lastReplayEventGroup != nil ? 128 : animationRate.live
        #if os(macOS)
        if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
            nextGameplayRate = animationRate.live
        }
        #endif
        super.init()
        gameScene.actionHandler = self
        addChild(gameScene)
    }
    
    required override init() {
        fatalError("init() has not been implemented")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func close() {
        gameplayRate = 0
        gameScene.close()
        gameScene.actionHandler = nil
        myUndoManager.removeAllActions()
        timeline.removeAllActions()
    }
    
    func load(data: GameRoom.StartGameResponse) async throws {
        setupOverlay()
        try await gameScene.load(localizedPlayers: players.map({ $0.localizedPlayer }), options: data.options)
        await withCheckedContinuation { continuation in
            GameViewController.shared.updateSpriteKit { [self] in
                addPlayers()
                setInitialState()
                if pendingEventGroups.isEmpty {
                    _isGameplayPaused = false
                } else {
                    handleEventGroup(pendingEventGroups.removeFirst())
                }
                continuation.resume()
            }
        }
    }
    
    private func setupOverlay() {
        overlay.gameMenu.undoButton.enable(false)
        overlay.gameMenu.redoButton.enable(false)
        if let gameOverlay = gameScene.overlay {
            overlay.gameOverlay = gameOverlay
            gameOverlay.zPosition = 2
        }
        
        if let hostPlayer = gameSceneContext.hostPlayer, players.contains(where: { $0.localizedPlayer.savedPlayer.host == hostPlayer }) {
            let button = ButtonNode2D()
            let image = ImageButton2D(systemName: "eye.circle", width: 80, color: .systemRed)
            image.position.y = 40
            let label = TextNode2D(string: "", fontSize: 25, shadowColor: .black.withAlphaComponent(0.9))
            label.position.y = -40
            button.addChild(image)
            button.addChild(label)
            changeLocalPlayer = (button, image, label)
        }
    }
    
    func layout(in frame: CGRect) {
        gameScene.layoutOverlay(in: frame)
    }
    
    private var myUndoManager: BoardGameKitHost.UndoManager {
        return gameSceneContext.gameContext.undoManager!
    }
    
    private var timeline: Timeline {
        return gameSceneContext.timeline
    }
    
    private func send<T: Request>(_ data: T) {
        ServerShared.send(data)
    }
    
    // MARK: - Handle request
    
    func eventGroup(data: GameManager.EventGroupResponse) {
        if timeline.isLive && !isGameplayPaused && (gameplayRate == 0 || data.isLiveAction) {
            handleEventGroup(data)
        } else {
            pendingEventGroups.append(data)
        }
    }
    
    private func checkPendingEventGroup() {
        if !pendingEventGroups.isEmpty {
            handleEventGroup(pendingEventGroups.removeFirst())
        } else if lastReplayEventGroup == nil {
            gameplayRate = 0
            nextGameplayRate = animationRate.live
            if hasEnded {
                if isGameEnabled {
                    isGameEnabled = false
                } else {
                    overlay.isTimelineVisible = true
                }
            } else if !isGameEnabled {
                overlay.isOverlayVisible = true
                overlay.isTimelineVisible = false
                isGameEnabled = true
            } else {
                setNextLocalPlayer()
            }
            if let hostPlayer = gameSceneContext.hostPlayer, players.first(id: hostPlayer)?.status == .connecting {
                send(GameRoom.ConnectedRequest())
            }
        }
    }
    
    private func handleEventGroup(_ eventGroup: GameManager.EventGroupResponse) {
        Logger.shared.debug("Handle event group \(eventGroup.id)")
        if let event = eventGroup.events.first, event.name == GameManager.UndoRequestResponse.name {
            gameplayRate = 0
            isGameEnabled = false
            let request = try! RequestCoder.decode(GameManager.UndoRequestResponse.self, from: Data(event.data.utf8))
            gameSceneContext.makeCurrent {
                myUndoManager.undo(to: request.eventGroup)
                timeline.undo(to: request.eventGroup, startAnimation: true)
            }
        } else {
            handleGameEventGroup(eventGroup)
            if eventGroup.id == lastReplayEventGroup {
                lastReplayEventGroup = nil
            }
            hasEnded = eventGroup.hasEnded == true
            if isGameEnabled, let localPlayer = localPlayer {
                gameScene.enableActions(true, for: localPlayer)
            }
            overlay.gameMenu.redoButton.enable(false)
        }
        if overlay.isTimelineVisible {
            GameViewController.shared.updateSpriteKit { [self] in
                overlay.timelineView.duration = timeline.duration
                overlay.timelineView.setMarkers(timeline.eventGroups.map({ $0.startTime }), liveTime: timeline.liveTime)
            }
        }
        if gameplayRate == 0 {
            gameplayRate = switch timeline.undoAnimation?.direction {
            case nil:
                nextGameplayRate
            case .backward:
                -(nextGameplayRate == animationRate.live ? animationRate.undo : nextGameplayRate)
            case .forward:
                nextGameplayRate == animationRate.live ? animationRate.undo : nextGameplayRate
            }
        }
    }
    
    private func handleGameEventGroup(_ eventGroup: GameManager.EventGroupResponse) {
        myUndoManager.beginUndoGrouping()
        timeline.beginUndoGrouping()
        gameSceneContext.makeCurrent {
            if let playerStateChanges = eventGroup.playerStateChanges {
                for state in playerStateChanges {
                    players.first(id: state.id)!.isWaiting = state.state == nil
                }
                overlay.playerStateScene.setPlayerStates(playerStateChanges)
            }
            do {
                try gameScene.handle(eventGroup: eventGroup)
            } catch {
                fatalError("Error during handling of event group \(eventGroup.id)\n\(error.localizedDescription)")
            }
        }
        myUndoManager.endUndoGrouping()
        timeline.endUndoGrouping(startAsyncAnimations: isGameEnabled)
    }
    
    func gameError(data: GameManager.GameErrorResponse) throws {
        myUndoManager.removeAllRedoActions()
        timeline.removeAllRedoActions()
        if let localPlayer = localPlayer {
            gameScene.enableActions(true, for: localPlayer)
        }
        try gameScene.handle(error: data)
    }
    
    // MARK: - Players
    
    private var focusedPlayer: Player?
    
    private func addPlayers() {
        if players.count != gameScene.players.count {
            preconditionFailure("Game scene didn't set up the players.")
        }
        for (player, customPlayer) in zip(players, gameScene.players) {
            player.player = customPlayer
            if let playerOverlay = customPlayer.overlay {
                player.overlay = playerOverlay
                playerOverlay.icon.setBorderColorAnimated(hasEnded ? .gray : player.status?.color ?? GameRoom.Status.botColor)
                playerOverlay.tap = { [unowned self, unowned player] _ in
                    focusedPlayer = player
                }
                overlay.playerOverlays.addChild(playerOverlay)
            }
        }
    }
    
    private func setInitialState() {
        if let hostPlayer = gameSceneContext.hostPlayer, !hasEnded {
            for player in players {
                gameScene.hidePrivateData(true, for: player)
            }
            if players.allSatisfy({ $0.localizedPlayer.savedPlayer.host != hostPlayer }) {
                localPlayer = players.first(id: hostPlayer)
            }
        }
        if focusedPlayer == nil {
            focusedPlayer = gameSceneContext.hostPlayer.flatMap({ players.first(id: $0) }) ?? players.first
        }
    }
    
    func statusChange(data: GameRoom.StatusChangeResponse) {
        for player in players.filter({ $0.id == data.player || $0.localizedPlayer.savedPlayer.host == data.player }) {
            player.status = data.status
            player.overlay?.icon.setBorderColorAnimated(data.status.color)
        }
    }
    
    // MARK: - State
    
    private var localPlayer: Player? {
        didSet {
            if let oldValue = oldValue {
                gameScene.hidePrivateData(true, for: oldValue)
                gameScene.enableActions(false, for: oldValue)
            }
            if let localPlayer = localPlayer {
                gameScene.hidePrivateData(false, for: localPlayer)
                gameScene.enableActions(true, for: localPlayer)
                focusedPlayer = localPlayer
            }
            gameScene.setLocalPlayer(localPlayer)
            setNextLocalPlayer()
        }
    }
    
    /// Shows or hides the button to change the local player. If `nextLocalPlayer` is equal to `localPlayer`, tapping the button hides the local player, otherwise it shows the next player.
    private var nextLocalPlayer: Player? {
        didSet {
            guard let changeLocalPlayer = changeLocalPlayer, nextLocalPlayer !== oldValue else {
                return
            }
            if let nextLocalPlayer = nextLocalPlayer {
                if nextLocalPlayer === localPlayer {
                    changeLocalPlayer.label.string = String(format: NSLocalizedString("game.player.hide", bundle: .boardGameKit, value: "Hide %@", comment: ""), nextLocalPlayer.localizedPlayer.name) // Calling SKLabelNode.frame very often in SCNView.overlaySKScene causes crash (FB14803512)
                    changeLocalPlayer.image.setSystemImage("eye.slash.circle", color: .systemGreen)
                    changeLocalPlayer.button.tap = { [self] _ in
                        localPlayer = nil
                        send(GameManager.ChangeLocalPlayerRequest(player: localPlayer?.id))
                    }
                } else {
                    changeLocalPlayer.label.string = String(format: NSLocalizedString("game.player.show", bundle: .boardGameKit, value: "Show %@", comment: ""), nextLocalPlayer.localizedPlayer.name)
                    changeLocalPlayer.image.setSystemImage("eye.circle", color: .systemRed)
                    changeLocalPlayer.button.tap = { [self] _ in
                        localPlayer = nextLocalPlayer
                        send(GameManager.ChangeLocalPlayerRequest(player: localPlayer?.id))
                    }
                }
                overlay.showChild(changeLocalPlayer.button, true)
            } else {
                changeLocalPlayer.button.tap = nil
                overlay.showChild(changeLocalPlayer.button, false)
            }
        }
    }
    
    private func setNextLocalPlayer() {
        nextLocalPlayer = if !isGameEnabled {
            nil
        } else if let localPlayer = localPlayer {
            localPlayer.isWaiting ? localPlayer : nil
        } else if let hostPlayer = gameSceneContext.hostPlayer {
            players.first(where: { ($0.id == hostPlayer || $0.localizedPlayer.savedPlayer.host == hostPlayer) && !$0.isWaiting })
        } else {
            nil
        }
    }
    
    /// The game is disabled during the initial replay, during undo and redo operations, while the gameplay is paused (including when the player is navigating the timeline) and when the game ends.
    private var isGameEnabled = false {
        didSet {
            if isGameEnabled == oldValue {
                return
            }
            overlay.gameMenu.undoButton.enable(timeline.canUndo && isGameEnabled)
            overlay.gameMenu.redoButton.enable(timeline.canRedo && isGameEnabled)
            setNextLocalPlayer()
            if let localPlayer = localPlayer {
                gameScene.enableActions(isGameEnabled, for: localPlayer)
            }
            if let gameOverlay = overlay.gameOverlay {
                if isGameEnabled {
                    overlay.addChildAndFadeIn(gameOverlay)
                } else {
                    gameOverlay.fadeOutAndRemoveFromParent()
                }
            }
        }
    }
    
    // MARK: - Animation
    
    private var _isGameplayPaused = true
    var isGameplayPaused: Bool {
        get {
            return _isGameplayPaused
        }
        set {
            if newValue == _isGameplayPaused {
                return
            }
            if newValue {
                isGameEnabled = false
                let currentTime = timeline.lastAsyncAnimationTime ?? timeline.currentTime
                timeline.completeAllAnimations()
                timeline.seek(to: currentTime)
                gameplayRate = 0
            } else {
                gameplayRate = nextGameplayRate
            }
            _isGameplayPaused = newValue // do this last since gameplayRate always sets it to false
        }
    }
    
    var gameplayRate = 0.0 {
        didSet {
            if gameplayRate == oldValue {
                return
            }
            if overlay.isTimelineVisible {
                GameViewController.shared.updateSpriteKit { [self] in
                    overlay.timelineView.rate = gameplayRate
                }
            }
            Logger.shared.debug("Set gameplay rate \(gameplayRate)")
            _isGameplayPaused = false
            if gameplayRate == 0 {
                stopAnimation()
            } else if timeline.hasAsyncAnimations {
                runAsyncAnimations()
            } else {
                let lastGameplayRateChange = (date: Date(), time: timeline.currentTime)
                startAnimation { [self] _ in
                    var time = lastGameplayRateChange.time - lastGameplayRateChange.date.timeIntervalSinceNow * gameplayRate
                    let undoAnimation = timeline.undoAnimation
                    time = switch undoAnimation {
                    case (_, let timeInterval)?:
                        max(timeInterval.lowerBound, min(time, timeInterval.upperBound))
                    case nil:
                        if (timeline.currentTime < timeline.liveTime && timeline.liveTime < time) || (time < timeline.liveTime && timeline.liveTime < timeline.currentTime) {
                            timeline.liveTime
                        } else {
                            max(0, min(timeline.duration, time))
                        }
                    }
                    timeline.seek(to: time)
                    if overlay.isTimelineVisible {
                        overlay.timelineView.currentTime = timeline.currentTime
                    }
                    if timeline.isLive {
                        if undoAnimation?.direction != timeline.undoAnimation?.direction {
                            gameplayRate = 0
                        }
                        checkPendingEventGroup()
                    } else if timeline.currentTime == 0 || timeline.currentTime == timeline.duration {
                        isGameplayPaused = true
                        nextGameplayRate = animationRate.live
                    }
                }
            }
        }
    }
    
    public func runAsyncAnimations() {
        var lastUpdate = Date()
        startAnimation { [self] _ in
            let date = Date()
            let timeOffset = max(0, date.timeIntervalSince(lastUpdate) * nextGameplayRate)
            lastUpdate = date
            timeline.seekAsyncAnimations(by: timeOffset)
            if !timeline.hasAsyncAnimations {
                checkPendingEventGroup()
            }
        }
    }
    
    private var animationId = 0
    private func startAnimation(block: @MainActor @escaping (_ t: Double) -> Void) {
        animationId += 1
        let animationId = animationId
        run(.customAction(withDuration: 999999) { _, t in // Using SCNAction.customAction(duration:action:) causes crash with Swift 6 language mode (FB15570385)
            Task { @MainActor in
                if animationId != self.animationId {
                    return
                }
                block(t)
            }
        }, withKey: "playback")
    }
    
    private func stopAnimation() {
        animationId += 1
        removeAction(forKey: "playback")
    }
    
    // MARK: - Game scene event handler
    
    /// After sending the given action, the local player is disabled. If they are still allowed to play when the next event group is received, they are enabled again.
    public func sendAction(_ action: any GameAction) {
        send(GameManager.GameActionRequest(action))
        if let localPlayer = localPlayer {
            gameScene.enableActions(false, for: localPlayer)
        }
    }

}

extension GameScene2D {
    
    func setLocalPlayer(_ player: GameSceneManager2D.Player?) {
        localPlayer = player?.player as? PlayerNode
    }
    
    func hidePrivateData(_ hide: Bool, for player: GameSceneManager2D.Player) {
        hidePrivateData(hide, for: player.player as! PlayerNode)
    }
    
    func enableActions(_ enable: Bool, for player: GameSceneManager2D.Player) {
        enableActions(enable, for: player.player as! PlayerNode)
    }
    
}
