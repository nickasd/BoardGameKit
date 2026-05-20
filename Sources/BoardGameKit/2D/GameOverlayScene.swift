import BoardGameKitHost
import SpriteKit
import SwiftUI
import StoreKit

public class GameOverlayScene: Scene2D {
    
    private let gameId: UUID?
    private var gameSceneManager: AnyGameSceneManager!
    private var isLoading = true
    private var hasEnded: Bool
    private var lastEventGroupId = 0
    private var reconnectAttempts = ServerShared is WebsocketServer ? 1 : 0
    private var showMenuButton: ImageButton2D!
    private let gameSceneContext = GameSceneContext.current
    let gameMenu = GameMenu()
    let timelineView = TimelineView()
    private(set) var playerStateScene: PlayerStateScene!
    private(set) var playerOverlays: SKNode!
    var gameOverlay: SKNode?
    
    private var lastReviewAsked: Date {
        get {
            return UserDefaults.standard.object(forKey: "lastReviewAsked") as? Date ?? .distantPast
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "lastReviewAsked")
        }
    }
    private let completedGamesBeforeReview = 3
    private let daysBeforeAnotherReview = TimeInterval(365)
    
    init(data: GameRoom.StartGameResponse, localizedPlayers: [LocalizedPlayer]) {
        gameId = data.id
        hasEnded = data.hasEnded
        super.init()
        switch ClientConfiguration.shared.scenes.game {
        case .scene3D:
            let gameSceneManager = GameSceneManager3D(data: data, localizedPlayers: localizedPlayers)
            self.gameSceneManager = gameSceneManager
            Scene3D.current.transition(to: gameSceneManager)
        case .scene2D:
            let gameSceneManager = GameSceneManager2D(data: data, localizedPlayers: localizedPlayers)
            self.gameSceneManager = gameSceneManager
            addChild(gameSceneManager)
        }
        gameSceneManager.overlay = self
        playerStateScene = PlayerStateScene(localizedPlayers: localizedPlayers)
        
        showMenuButton = ImageButton2D(systemName: "ellipsis.circle")
        showMenuButton.tap = { [unowned self] _ in
            isMenuVisible.toggle()
        }
        showMenuButton.zPosition = 11
        addChild(showMenuButton)
        
        gameMenu.homeButton.tap = { [unowned self] _ in
            switch ClientConfiguration.shared.scenes.game {
            case .scene3D:
                Scene3D.current.transition(to: MainScene())
            case .scene2D:
                transition(to: ClientConfiguration.shared.scenes.mainMenu.init())
            }
        }
        gameMenu.pauseButton.tap = { [unowned self] _ in
            isMenuVisible = false
            toggleGameplayPaused()
        }
        gameMenu.undoButton.tap = { [unowned self] _ in
            undo()
        }
        gameMenu.redoButton.tap = { [unowned self] _ in
            redo()
        }
        gameMenu.helpButton.tap = { [unowned self] _ in
            isMenuVisible = false
            transition(to: HelpScene())
        }
        gameMenu.showPlayerStateButton.tap = { [unowned self] _ in
            isMenuVisible = false
            playerStateScene.activate()
            transition(to: playerStateScene)
        }
        gameMenu.zPosition = 10
        
        timelineView.forwardButton.tap = { [unowned self] _ in
            increaseGameplayRate()
        }
        timelineView.playButton.tap = { [unowned self] _ in
            gameSceneManager.isGameplayPaused.toggle()
        }
        timelineView.backwardButton.tap = { [unowned self] _ in
            decreaseGameplayRate()
        }
        timelineView.barContainer.tap = { [unowned self] in
            setTimelineKnob($0)
        }
        timelineView.barContainer.drag = (start: { [unowned self] in
            dragTimelineKnobStart($0)
        }, update: { [unowned self] in
            dragTimelineKnobUpdate($0, to: $1)
        }, end: { [unowned self] in
            dragTimelineKnobEnd($0)
        })
        timelineView.zPosition = 9

        playerOverlays = SKNode()
        playerOverlays.zPosition = 1
        addChild(playerOverlays)
        
        let loadingLabel = TextNode2D(string: NSLocalizedString("loading", bundle: .boardGameKit, value: "Loading...", comment: ""))
        addChild(loadingLabel)
        Task {
            do {
                try await gameSceneManager.load(data: data)
                isLoading = false
                GameViewController.shared.updateSpriteKit { [self] in
                    layoutDynamicOverlay()
                }
                loadingLabel.fadeOutAndRemoveFromParent()
                ClientConfiguration.shared.scenes.mainMenu.setBackground(nil, size: .zero)
            } catch {
                fatalError(error.localizedDescription)
            }
        }
    }
    
    required override init() {
        fatalError("init() has not been implemented")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func willAppear() {
        if Scene2D.current is GameRoomScene || Scene2D.current is GameOverlayScene {
            addHandle(eventGroup)
            addHandle(gameError)
            addHandle(register)
            addHandle(getLobby)
            addHandle(joinGame)
            addHandle(getGameRoom)
            addHandle(joinGameRoom)
            addHandle(leaveGameRoom)
            addHandle(statusChange)
            addHandle(archiveGame)
            
            ServerShared.delegate = self
        }
    }
    
    public override func transition(to scene: Scene2D) {
        if scene is MainMenuScene || scene is GameOverlayScene {
            removeAllHandles()
            gameSceneManager.close()
        }
        super.transition(to: scene)
    }
    
    private var timeline: Timeline {
        return gameSceneContext.timeline
    }
    
    public override func layout() {
        super.layout()
        showMenuButton.position = CGPoint(x: sceneFrame.maxX - 50, y: sceneFrame.maxY - 50)
        gameMenu.position = showMenuButton.position
        timelineView.position = CGPoint(x: 0, y: sceneFrame.minY * 0.8)
        layoutDynamicOverlay()
    }
    
    func layoutDynamicOverlay() {
        if isLoading {
            return
        }
        gameSceneManager.layout(in: sceneFrame)
    }
    
    override func hitTest(at point: CGPoint) -> Scene2D.HitTestResult? {
        let result = super.hitTest(at: point)
        return ![gameOverlay, playerOverlays].contains(result?.node) ? result : nil
    }
    
    private var isMenuVisible = false {
        didSet {
            if isMenuVisible == oldValue {
                return
            }
            if isMenuVisible {
                GameViewController.shared.updateSpriteKit { [self] in
                    showMenuButton.setSystemImage("ellipsis.circle.fill")
                    addChildAndFadeIn(gameMenu)
                }
            } else {
                GameViewController.shared.updateSpriteKit { [self] in
                    showMenuButton.setSystemImage("ellipsis.circle")
                    gameMenu.fadeOutAndRemoveFromParent()
                }
            }
            #if os(macOS)
            GameViewController.shared.scnView?.needsDisplay = true // SceneKit overlay view is not drawn until performing scroll gesture (FB14155213)
            #else
            GameViewController.shared.scnView?.setNeedsDisplay() // SceneKit overlay view is not drawn until performing scroll gesture (FB14155213)
            #endif
        }
    }
    
    var isTimelineVisible = false {
        didSet {
            if isTimelineVisible == oldValue {
                return
            }
            if isTimelineVisible {
                GameViewController.shared.updateSpriteKit { [self] in
                    timelineView.duration = timeline.duration
                    timelineView.setMarkers(timeline.eventGroups.map({ $0.startTime }), liveTime: timeline.liveTime)
                    timelineView.currentTime = timeline.currentTime
                    
                    gameOverlay?.fadeOutAndRemoveFromParent()
                    gameMenu.pauseButton.setSystemImage("play.circle")
                    addChildAndFadeIn(timelineView)
                }
            } else {
                GameViewController.shared.updateSpriteKit { [self] in
                    gameMenu.pauseButton.setSystemImage("pause.circle")
                    timelineView.fadeOutAndRemoveFromParent()
                    if let gameOverlay = gameOverlay {
                        addChildAndFadeIn(gameOverlay)
                    }
                }
            }
            #if os(macOS)
            GameViewController.shared.scnView?.needsDisplay = true // SceneKit overlay view is not drawn until performing scroll gesture (FB14155213)
            #else
            GameViewController.shared.scnView?.setNeedsDisplay() // SceneKit overlay view is not drawn until performing scroll gesture (FB14155213)
            #endif
        }
    }
    
    var isOverlayVisible = true {
        didSet {
            if isOverlayVisible == oldValue {
                return
            }
            if isOverlayVisible {
                GameViewController.shared.updateSpriteKit { [self] in
                    addChildAndFadeIn(timelineView)
                    addChildAndFadeIn(showMenuButton)
                }
            } else {
                isMenuVisible = false
                GameViewController.shared.updateSpriteKit { [self] in
                    timelineView.fadeOutAndRemoveFromParent()
                    showMenuButton.fadeOutAndRemoveFromParent()
                }
            }
        }
    }
    
    // MARK: - Timeline
    
    @available(macOS 14.0, iOS 17.0, *)
    public func onKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        if isLoading {
            return .ignored
        }
        switch keyPress.characters.lowercased() {
        case "j":
            decreaseGameplayRate()
            return .handled
        case "k", " ":
            toggleGameplayPaused()
            return .handled
        case "l":
            increaseGameplayRate()
            return .handled
        case "z":
            if keyPress.modifiers.contains(.command) {
                if keyPress.modifiers.contains(.shift) {
                    if gameMenu.redoButton.isEnabled && timeline.canRedo {
                        redo()
                    }
                } else {
                    if gameMenu.undoButton.isEnabled && timeline.canUndo {
                        undo()
                    }
                }
                return .handled
            } else {
                return .ignored
            }
        default:
            return .ignored
        }
    }
    
    private func increaseGameplayRate() {
        let gameplayRate = gameSceneManager.gameplayRate
        if !isTimelineVisible && timeline.liveTime != timeline.duration {
            gameSceneManager.isGameplayPaused = true
            isTimelineVisible = true
        }
        gameSceneManager.gameplayRate = if gameplayRate == 0 || gameplayRate < -1 {
            1
        } else if gameplayRate < 0 {
            abs(gameplayRate)
        } else {
            #if os(macOS)
            gameplayRate * (NSEvent.modifierFlags.contains(.option) ? 0.5 : 2)
            #else
            gameplayRate * 2
            #endif
        }
    }
    
    private func decreaseGameplayRate() {
        let gameplayRate = gameSceneManager.gameplayRate
        if !isTimelineVisible {
            gameSceneManager.isGameplayPaused = true
            isTimelineVisible = true
        }
        gameSceneManager.gameplayRate = if gameplayRate == 0 || gameplayRate > 1 {
            -1
        } else if gameplayRate > 0 {
            -abs(gameplayRate)
        } else {
            #if os(macOS)
            gameplayRate * (NSEvent.modifierFlags.contains(.option) ? 0.5 : 2)
            #else
            gameplayRate * 2
            #endif
        }
    }
    
    private func toggleGameplayPaused() {
        isTimelineVisible = true
        gameSceneManager.isGameplayPaused.toggle()
    }
    
    private func undo() {
        send(GameManager.UndoRequestResponse(eventGroup: timeline.currentEventGroup - 1))
    }
    
    private func redo() {
        send(GameManager.UndoRequestResponse(eventGroup: timeline.currentEventGroup + 1))
    }
    
    private func setTimelineKnob(_ result: Scene2D.HitTestResult) {
        gameSceneManager.isGameplayPaused = true
        let point = timelineView.convert(result.point, from: result.sender.scene!)
        let t = max(0, min((point.x - timelineView.barFrame.minX) / timelineView.barFrame.width, 1))
        timeline.seek(to: t * timeline.duration)
        timelineView.currentTime = timeline.currentTime
    }
    
    private func dragTimelineKnobStart(_ sender: ButtonNode2D) -> ButtonNode2D {
        gameSceneManager.isGameplayPaused = true
        return sender
    }

    private func dragTimelineKnobUpdate(_ node: ButtonNode2D, to point: CGPoint) {
        let point = timelineView.convert(point, from: node.scene!)
        let t = max(0, min((point.x - timelineView.barFrame.minX) / timelineView.barFrame.width, 1))
        timeline.seek(to: t * timeline.duration)
        timelineView.currentTime = timeline.currentTime
    }

    private func dragTimelineKnobEnd(_ sender: ButtonNode2D) {
    }
    
    // MARK: - Handles
    
    private func eventGroup(data: GameManager.EventGroupResponse) {
        lastEventGroupId = data.id
        gameSceneManager.eventGroup(data: data)
        if !hasEnded && data.hasEnded == true {
            hasEnded = true
            requestReviewIfNecessary()
        }
    }
    
    private func gameError(data: GameManager.GameErrorResponse) throws {
        try gameSceneManager.gameError(data: data)
    }
    
    private func register(data: WebSocketGameHost.RegisterResponse) {
    }
    
    private func getLobby(data: Lobby.GetLobbyResponse) {
    }
    
    private func joinGame(data: Lobby.JoinGameResponse) {
    }
    
    private func getGameRoom(data: GameRoom.GetGameRoomResponse) {
    }
    
    private func joinGameRoom(data: GameRoom.JoinGameRoomResponse) {
    }
    
    private func leaveGameRoom(data: GameRoom.LeaveGameRoomResponse) {
    }
    
    private func statusChange(data: GameRoom.StatusChangeResponse) {
        gameSceneManager.statusChange(data: data)
    }
    
    private func archiveGame(data: GameManager.ArchiveGameResponse) {
        do {
            try LocalGames.shared.archiveGame(data.game, name: data.name)
        } catch {
            showError(error)
        }
    }
    
    private func requestReviewIfNecessary() {
        if LocalGames.shared.archivedGames().count >= completedGamesBeforeReview {
            if -lastReviewAsked.timeIntervalSinceNow > 60 * 60 * 24 * daysBeforeAnotherReview {
                lastReviewAsked = Date()
                DispatchQueue.main.asyncAfter(deadline: .now() + timeline.duration - (timeline.lastAsyncAnimationTime ?? timeline.currentTime) + 3) {
                    #if os(macOS)
                    SKStoreReviewController.requestReview()
                    #else
                    SKStoreReviewController.requestReview(in: UIApplication.shared.connectedScenes.first as! UIWindowScene)
                    #endif
                }
            }
        }
    }
    
    // MARK: - Server
    
    public override func serverDidConnect(_ server: Server) {
        guard let gameId = gameId else {
            return
        }
        reconnectAttempts = ServerShared is WebsocketServer ? 1 : 0
        send(WebSocketGameHost.RegisterRequest(user: User.savedOnlineUser))
        send(Lobby.JoinGameRequest(game: gameId))
        send(GameRoom.ReconnectRequest(player: nil, eventGroupId: lastEventGroupId))
    }
    
    public override func serverDidDisconnect(_ server: Server) {
        if reconnectAttempts > 0 {
            ServerShared.connect()
            reconnectAttempts -= 1
        } else if case .scene3D = ClientConfiguration.shared.scenes.game {
            Scene3D.current.transition(to: MainScene())
        } else {
            super.serverDidDisconnect(server)
        }
    }
    
    public override func serverShouldReinvitePlayer(_ server: any Server) -> Bool {
        return !hasEnded
    }
    
}

class GameMenu: SKNode {
    
    private(set) var helpButton: ImageButton2D!
    private(set) var undoButton: ImageButton2D!
    private(set) var redoButton: ImageButton2D!
    private(set) var pauseButton: ImageButton2D!
    private(set) var showPlayerStateButton: ImageButton2D!
    #if os(iOS)
    private(set) var setARModeButton: ImageButton2D!
    #endif
    private(set) var homeButton: ImageButton2D!
    
    override init() {
        super.init()
        let background = SKShapeNode(rect: CGRect(origin: .zero, size: CGSize(width: -640, height: 0)).insetBy(dx: -40, dy: -40), cornerRadius: 40)
        background.fillColor = Color(white: 0.2, alpha: 0.95)
        background.strokeColor = .white.withAlphaComponent(0.5)
        addChild(background)
        
        helpButton = ImageButton2D(systemName: "questionmark.circle")
        helpButton.enable(ClientConfiguration.shared.scenes.rules != nil)
        helpButton.position = CGPoint(x: -80, y: 0)
        addChild(helpButton)
        
        redoButton = ImageButton2D(systemName: "arrowshape.turn.up.forward.circle")
        redoButton.position = CGPoint(x: -180, y: 0)
        addChild(redoButton)
        
        undoButton = ImageButton2D(systemName: "arrowshape.turn.up.backward.circle")
        undoButton.position = CGPoint(x: -260, y: 0)
        addChild(undoButton)
        
        showPlayerStateButton = ImageButton2D(systemName: "clock.circle")
        showPlayerStateButton.position = CGPoint(x: -360, y: 0)
        addChild(showPlayerStateButton)
        
        pauseButton = ImageButton2D(systemName: "pause.circle")
        pauseButton.position = CGPoint(x: -440, y: 0)
        addChild(pauseButton)
        
        #if os(iOS)
        setARModeButton = ImageButton2D(systemName: "eye.circle")
        setARModeButton.tap = { [unowned self] _ in
            GameViewController.shared.arViewDelegate.toggleARMode()
            setARModeButton.setSystemImage(GameViewController.shared.arViewDelegate.isARMode ? "eye.circle.fill" : "eye.circle")
        }
        setARModeButton.position = CGPoint(x: -540, y: 0)
        addChild(setARModeButton)
        #endif
        
        homeButton = ImageButton2D(systemName: "house.circle")
        homeButton.position = CGPoint(x: -640, y: 0)
        addChild(homeButton)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}

protocol AnyGameSceneManager {
    var overlay: GameOverlayScene! { get set }
    @MainActor func load(data: GameRoom.StartGameResponse) async throws
    func layout(in frame: CGRect)
    func close()
    func eventGroup(data: GameManager.EventGroupResponse)
    func gameError(data: GameManager.GameErrorResponse) throws
    func statusChange(data: GameRoom.StatusChangeResponse)
    var isGameplayPaused: Bool { get set }
    var gameplayRate: Double { get set }
}
