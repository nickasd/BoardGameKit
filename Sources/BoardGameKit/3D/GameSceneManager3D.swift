import BoardGameKitHost
import SceneKit
import SpriteKit

public class GameSceneManager3D: Scene3D, GameSceneActionHandler3D, AnyGameSceneManager {
    
    class Player: Identifiable {
        
        let localizedPlayer: LocalizedPlayer
        var status: GameRoom.Status?
        var player: (any GamePlayerNode3D)!
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
    public let gameScene: any GameScene3D
    private let players: [Player]
    weak var overlay: GameOverlayScene!
    private(set) var hasEnded: Bool
    private let animationRate = (live: TimeInterval(1), undo: TimeInterval(4))
    private var lastReplayEventGroup: Int?
    private var nextGameplayRate: Double
    private var pendingEventGroups = [GameManager.EventGroupResponse]()
    private var changeLocalPlayer: (button: ButtonNode2D, image: ImageButton2D, label: TextNode2D)?
    
    init(data: GameRoom.StartGameResponse, localizedPlayers: [LocalizedPlayer]) {
        gameScene = if case .scene3D(let gameScene) = ClientConfiguration.shared.scenes.game {
            gameScene.init()
        } else {
            preconditionFailure()
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
        addChildNode(gameScene)
        
        allowsCameraControl = true
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
        gameScene.releaseCheckpoints(node: self)
        undoManager.removeAllActions()
        timeline.removeAllActions()
    }
    
    func load(data: GameRoom.StartGameResponse) async throws {
        setupOverlay()
        try await gameScene.load(localizedPlayers: players.map({ $0.localizedPlayer }), options: data.options)
        addPlayers()
        setInitialState()
        if pendingEventGroups.isEmpty {
            _isGameplayPaused = false
        } else {
            handleEventGroup(pendingEventGroups.removeFirst())
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
    
    private var undoManager: BoardGameKitHost.UndoManager {
        return gameSceneContext.gameContext.undoManager!
    }
    
    private var timeline: Timeline {
        return gameSceneContext.timeline
    }
    
    private func send<T: Request>(_ data: T) {
        ServerShared.send(data)
    }
    
    public override func tapNothing() {
        if !overlay.isOverlayVisible {
            overlay.isOverlayVisible = true
        } else if overlay.isTimelineVisible {
            overlay.isOverlayVisible = false
        }
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
                undoManager.undo(to: request.eventGroup)
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
        undoManager.beginUndoGrouping()
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
        undoManager.endUndoGrouping()
        timeline.endUndoGrouping(startAsyncAnimations: isGameEnabled)
    }
    
    func gameError(data: GameManager.GameErrorResponse) throws {
        undoManager.removeAllRedoActions()
        timeline.removeAllRedoActions()
        if let localPlayer = localPlayer {
            gameScene.enableActions(true, for: localPlayer)
        }
        try gameScene.handle(error: data)
    }
    
    // MARK: - Players
    
    private var focusedPlayer: Player? {
        didSet {
            if let focusedPlayer = focusedPlayer {
                let transform = gameScene.cameraTransform(for: focusedPlayer)
                if oldValue == nil {
                    moveCamera(to: transform)
                } else {
                    Scene3D.mainCamera.runAction(focusPlayerAction(to: transform), forKey: "move")
                }
            }
            gameScene.setFocusedPlayer(focusedPlayer)
        }
    }
    
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
    
    private func focusPlayerAction(to toTransform: Transform) -> SCNAction {
        let duration = TimeInterval(0.5)
        let fromTransform = Scene3D.mainCamera.myTransform
        let fromPosition = fromTransform.position
        let fromRotation = fromTransform.rotation
        let toPosition = toTransform.position
        let toRotaion = toTransform.rotation
        let from = (angle: atan2(fromPosition.z, fromPosition.x), radius: simd_length(Vector3(x: fromPosition.x, y: 0, z: fromPosition.z)))
        let toAngle = atan2(toPosition.z, toPosition.x)
        let to = (angle: toAngle < from.angle - .pi - 0.00001 ? toAngle + .pi * 2 : toAngle > from.angle + .pi + 0.00001 ? toAngle - .pi * 2 : toAngle, radius: simd_length(Vector3(x: toPosition.x, y: 0, z: toPosition.z)))
        return .customAction(duration: duration) { node, t in // Using SCNAction.customAction(duration:action:) causes crash with Swift 6 language mode (FB15570385)
            let t = Float(t) / Float(duration)
            let angle = simd_mix(from.angle, to.angle, t)
            let radius = simd_mix(from.radius, to.radius, t)
            Scene3D.mainCamera.simdPosition = Vector3(x: cos(angle) * radius, y: simd_mix(fromPosition.y, toPosition.y, t), z: sin(angle) * radius)
            Scene3D.mainCamera.simdOrientation = simd_slerp(fromRotation, toRotaion, t)
        }.withTimingMode(.easeInEaseOut)
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
                    GameViewController.shared.updateSpriteKit {
                        changeLocalPlayer.label.string = String(format: NSLocalizedString("game.player.hide", bundle: .boardGameKit, value: "Hide %@", comment: ""), nextLocalPlayer.localizedPlayer.name) // Calling SKLabelNode.frame very often in SCNView.overlaySKScene causes crash (FB14803512)
                        changeLocalPlayer.image.setSystemImage("eye.slash.circle", color: .systemGreen)
                    }
                    changeLocalPlayer.button.tap = { [unowned self] _ in
                        localPlayer = nil
                        send(GameManager.ChangeLocalPlayerRequest(player: localPlayer?.id))
                    }
                } else {
                    GameViewController.shared.updateSpriteKit {
                        changeLocalPlayer.label.string = String(format: NSLocalizedString("game.player.show", bundle: .boardGameKit, value: "Show %@", comment: ""), nextLocalPlayer.localizedPlayer.name)
                        changeLocalPlayer.image.setSystemImage("eye.circle", color: .systemRed)
                    }
                    changeLocalPlayer.button.tap = { [unowned self] _ in
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
        runAction(.customAction(duration: 999999) { _, t in // Using SCNAction.customAction(duration:action:) causes crash with Swift 6 language mode (FB15570385)
            Task { @MainActor in
                if animationId != self.animationId {
                    return
                }
                block(t)
            }
        }, forKey: "playback")
    }
    
    private func stopAnimation() {
        animationId += 1
        removeAction(forKey: "playback")
    }
    
    // MARK: - Drag and drop
    
    public override func dragNodeStart(_ result: Scene3D.HitTestResult) -> ButtonNode3D {
        let node = result.sender.drag!.start(result)
        if node.parent == nil {
            preconditionFailure("Dragged node has no parent.")
        }
        if let (i, dropPoint) = node.dropPoints.enumerated().first(where: { $0.element.parent.parent == nil }) {
            preconditionFailure("Drop point \(i) has parent \(dropPoint.parent.description) that has not been added to the scene.")
        }
        return node
    }
    
    func didUpdateDropPoints(of node: ButtonNode3D, oldDropPoints: [ButtonNode3D.DropPoint]) {
        if let activeDropPoint = node.activeDropPoint {
            let activeDropPoint = [GameViewController.shared.scnView!.projectPoint(SCNVector3(oldDropPoints[activeDropPoint].parent.simdConvertPosition(oldDropPoints[activeDropPoint].transform.position, to: nil)))].map({ Vector2(x: Float($0.x), y: Float($0.y)) })[0]
            let dropPoints = node.dropPoints.map({ GameViewController.shared.scnView!.projectPoint(SCNVector3($0.parent.simdConvertPosition($0.transform.position, to: nil))) }).map({ Vector2(x: Float($0.x), y: Float($0.y)) })
            let (closestDropPoint, _) = dropPoints.enumerated().map({ i, dropPoint in (i: i, distance: simd_distance(dropPoint, activeDropPoint)) }).min(by: { $0.distance < $1.distance })!
            node.activeDropPoint = closestDropPoint
            draggedNode(node, enteredDropPoint: closestDropPoint)
        }
    }
    
    public override func dragNode(_ node: ButtonNode3D, to point: CGPoint) {
        let dropPoints = node.dropPoints.map({ GameViewController.shared.scnView!.projectPoint(SCNVector3($0.parent.simdConvertPosition($0.transform.position, to: nil))) }).map({ Vector2(x: Float($0.x), y: Float($0.y)) })
        let (activeDropPoint, distance) = dropPoints.enumerated().map({ i, dropPoint in (i: i, distance: simd_distance(dropPoint, Vector2(x: Float(point.x), y: Float(point.y)))) }).min(by: { $0.distance < $1.distance })!
        if activeDropPoint != node.activeDropPoint {
            draggedNode(node, enteredDropPoint: distance > 200 ? 0 : activeDropPoint)
        }
    }
    
    private func draggedNode(_ node: ButtonNode3D, enteredDropPoint activeDropPoint: Int) {
        node.activeDropPoint = activeDropPoint
        let dropPoint = node.dropPoints[activeDropPoint]
        node.runAction(.transform(node.parent!.convertTransform(dropPoint.transform, from: dropPoint.parent), duration: 0.3).withTimingMode(.easeOut), forKey: "move")
    }
    
    public override func dropDraggedNode(_ node: ButtonNode3D, sender: ButtonNode3D) {
        if let activeDropPoint = node.activeDropPoint {
            let dragEnd = sender.drag?.end
            node.dropPoints[activeDropPoint].action(node)
            node.activeDropPoint = nil
            dragEnd?(node)
        }
    }
    
    // MARK: - Game scene event handler
    
    /// After sending the given action, the local player is disabled. If they are still allowed to play when the next event group is received, they are enabled again.
    public func sendAction(_ action: any GameAction) {
        send(GameManager.GameActionRequest(action))
        if let localPlayer = localPlayer {
            gameScene.enableActions(false, for: localPlayer)
        }
    }
    
    public func showEndGameRanking(_ ranking: [(player: UUID, text: String)]) {
        var buttons = [ImageButton2D]()
        let homeButton = ImageButton2D(systemName: "house.circle")
        homeButton.tap = { [unowned self] _ in
            transition(to: MainScene())
        }
        buttons.append(homeButton)
        if isGameEnabled && GameHostShared is LocalGameHost {
            let playAgainButton = ImageButton2D(systemName: "arrow.counterclockwise.circle")
            playAgainButton.tap = { [unowned self] _ in
                overlay.addHandle(playAgain)
                send(GameRoom.PlayAgainRequest())
            }
            buttons.append(playAgainButton)
        }
        let scoreView = EndGameScoreView(localizedPlayers: players.map({ $0.localizedPlayer }), ranking: ranking, buttons: buttons)
        if case let frame = scoreView.calculateAccumulatedFrame(), frame.height > 350 {
            scoreView.setScale(350 / frame.height)
        }
        timeline.addAnimation(TimelineAnimation(id: "GameSceneManager.showEndGameRanking", subject: scoreView, startTime: timeline.currentTime + timeline.timeOffset, duration: 1, enter: { [self] direction in
            if direction == .forward {
                overlay.playerOverlays.addChild(scoreView)
            }
        }, progress: { t in
            scoreView.alpha = t
        }, exit: { direction in
            if direction == .backward {
                scoreView.removeFromParent()
            }
        }))
    }
    
    private func playAgain(data: GameRoom.StartGameResponse) {
        GameSceneContext(gameContext: GameContext(undoManager: UndoManager()), isPhone: gameSceneContext.isPhone, hostPlayer: gameSceneContext.hostPlayer).makeCurrent {
            overlay.transition(to: GameOverlayScene(data: data, localizedPlayers: data.players.map({ LocalizedPlayer(savedPlayer: $0, savedPlayers: data.players) })))
        }
    }

}

extension GameScene3D {
    
    func setLocalPlayer(_ player: GameSceneManager3D.Player?) {
        localPlayer = player?.player as? PlayerNode
    }
    
    func setFocusedPlayer(_ player: GameSceneManager3D.Player?) {
        focusedPlayer = player?.player as? PlayerNode
    }
    
    func hidePrivateData(_ hide: Bool, for player: GameSceneManager3D.Player) {
        hidePrivateData(hide, for: player.player as! PlayerNode)
    }
    
    func enableActions(_ enable: Bool, for player: GameSceneManager3D.Player) {
        enableActions(enable, for: player.player as! PlayerNode)
    }
    
    func cameraTransform(for player: GameSceneManager3D.Player) -> Transform {
        return cameraTransform(for: player.player as! PlayerNode)
    }
    
}
