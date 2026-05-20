import BoardGameKitHost
import SpriteKit

public class GameRoomScene: Scene2D {
    
    enum ViewType {
        case players
        case options
        case summary
    }
    
    class PlayerView: ButtonNode2D {
        
        let player: GameRoomModel.Player
        let icon: PlayerIcon
        
        init(player: GameRoomModel.Player, borderColor: Color) {
            self.player = player
            let size = 120.0
            icon = PlayerIcon(size: size, name: player.localizedPlayer.gameCharacter?.icon, borderWidth: 8, borderColor: borderColor)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            let label = TextNode2D(attributedString: NSAttributedString(string: player.localizedPlayer.name.replacingOccurrences(of: " (", with: "\n("), attributes: [.font: ClientConfiguration.shared.theme.labelFont(size: 25), .foregroundColor: Color.white, .paragraphStyle: paragraphStyle]), verticalAlignment: .top, maxWidth: size)
            label.position.y = -(size / 2 + 10)
            super.init()
            addChild(icon)
            addChild(label)
        }
        
        required init?(coder aDecoder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
    }
    
    public struct GameRoomModel {
        public class Player {
            
            public let user: User?
            public fileprivate(set) var status: GameRoom.Status?
            public let localizedPlayer: LocalizedPlayer
            
            init(user: User?, status: GameRoom.Status?, localizedPlayer: LocalizedPlayer) {
                self.user = user
                self.status = status
                self.localizedPlayer = localizedPlayer
            }
            
        }
        
        let id: UUID
        let name: String
        let hasStarted: Bool
        let isRemovable: Bool
        let hasEnded: Bool
        public fileprivate(set) var players: [Player]
        fileprivate(set) var observers: [User]
    }
    
    private var previousScene: Scene2D!
    private var background: SKShapeNode!
    private var title: SKNode!
    private var backButton: BackButton!
    private var titleLabel: TextNode2D!
    private var content: SKNode!
    private var playersView: GameRoomPlayersView?
    private var optionsView: (any GameOptionsView)?
    private var summaryView: SKNode!
    private var playerViews = [PlayerView]()
    private var startButton: TextButton2D!
    public private(set) var gameRoom: GameRoomModel!
    private var optionsVersion = 0
    private var options: Data!
    private var impersonatedPlayer: UUID?
    
    public required override init() {
        super.init()
        
        background = SKShapeNode()
        background.fillColor = Color(white: 0.2, alpha: 0.95)
        background.lineWidth = 0
        addChild(background)
        
        title = createTitle()
        addChild(title)
        
        content = SKNode()
        addChild(content)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func willAppear() {
        previousScene = Scene2D.current
        
        addHandle(getGameRoom)
        addHandle(joinGameRoom)
        addHandle(leaveGameRoom)
        addHandle(statusChange)
        addHandle(setBotStrategy)
        addHandle(setOptions)
        addHandle(startGame)
        addHandle(getGameArchive)
        
        ServerShared.delegate = self
    }
    
    public override func transition(to scene: Scene2D) {
        removeAllHandles()
        super.transition(to: scene)
    }
    
    public override var frame: CGRect {
        return if GameViewController.isPhone {
            CGRect(x: 0, y: 0, width: 800, height: 500)
        } else {
            CGRect(x: 0, y: 0, width: 800, height: 600)
        }
    }
    
    public override func layout() {
        super.layout()
        background.path = CGPath(rect: unsafeSceneFrame, transform: nil)
        if GameViewController.isPhone {
            title.position = CGPoint(x: sceneFrame.minX + 50, y: sceneFrame.maxY - 50)
        } else {
            title.position = CGPoint(x: sceneFrame.minX + 100, y: sceneFrame.maxY - 100)
        }
    }
    
    private var viewType = ViewType.players {
        didSet {
            content.children.last?.fadeOutAndRemoveFromParent()
            let view: SKNode
            switch viewType {
            case .players:
                view = playersView!
            case .options:
                view = optionsView!
            case .summary:
                for playerView in playerViews {
                    playerView.removeFromParent()
                }
                playerViews.removeAll()
                for (player, position) in zip(gameRoom.players, playerViewPositions()) {
                    let playerView = PlayerView(player: player, borderColor: gameRoom.hasEnded ? .gray : player.status?.color ?? GameRoom.Status.botColor)
                    if GameHostShared is LocalGameHost && player.status == .dropped && player.localizedPlayer.savedPlayer.host == nil {
                        playerView.tap = { [unowned self] _ in
                            startButton.string = NSLocalizedString("menu.game.rejoin", bundle: .boardGameKit, value: "Rejoin", comment: "")
                            impersonatedPlayer = player.localizedPlayer.savedPlayer.id
                        }
                    }
                    playerView.position = position
                    playerViews.append(playerView)
                    summaryView.addChild(playerView)
                }
                view = summaryView!
            }
            content.addChildAndFadeIn(view)
        }
    }
    
    private func createTitle() -> SKNode {
        let title = SKNode()
        
        backButton = BackButton()
        backButton.tap = { [unowned self] _ in
            switch viewType {
            case .players:
                if !(ServerShared is GameCenterServer) {
                    send(GameRoom.LeaveGameRoomRequest())
                }
                transition(to: previousScene)
                previousScene = nil
            case .options:
                viewType = .players
            case .summary:
                if gameRoom.hasStarted {
                    send(GameRoom.LeaveGameRoomRequest())
                    transition(to: previousScene)
                    previousScene = nil
                } else {
                    viewType = optionsView != nil ? .options : .players
                }
            }
        }
        backButton.position = CGPoint(x: 0, y: 0)
        title.addChild(backButton)
        
        titleLabel = TextNode2D(string: "", fontSize: 40, horizontalAlignment: .left, verticalAlignment: .center)
        titleLabel.position = CGPoint(x: 50, y: 0)
        title.addChild(titleLabel)
        
        return title
    }
    
    private func createOptionsView() -> (any GameOptionsView)? {
        guard let view = ClientConfiguration.shared.scenes.options?.init() else {
            return nil
        }
        view.gameRoomScene = self
        let nextButton = TextButton2D(string: NSLocalizedString("button.next", bundle: .boardGameKit, value: "Next", comment: ""), backgroundImageIndex: 0)
        nextButton.tap = { [unowned self] _ in
            viewType = .summary
        }
        nextButton.position = CGPoint(x: 0, y: -220)
        view.addChild(nextButton)
        return view
    }
    
    private func createSummaryView() -> SKNode {
        let view = SKNode()
        
        #if DEBUG
        if !gameRoom.hasStarted {
            let toggleObserverButton = TextButton2D(string: "Become Observer (Debug)", fontSize: 20, backgroundImageIndex: 1)
            toggleObserverButton.tap = { [unowned self] _ in
                send(GameRoom.SetObserverRequestResponse(observer: true))
            }
            toggleObserverButton.position = CGPoint(x: 0, y: -270)
            view.addChild(toggleObserverButton)
        }
        #endif

        startButton = TextButton2D(string: "", fontSize: 40, backgroundImageIndex: 0)
        startButton.position = CGPoint(x: 0, y: -220)
        view.addChild(startButton)
        
        return view
    }
    
    private func updatePlayerCount() {
        optionsView?.updatePlayers()
        playersView?.players = gameRoom.players
        startButton.enable(HostConfiguration.shared.game.requiredPlayerCount.contains(gameRoom.players.count))
    }
    
    private func playerViewPositions() -> [CGPoint] {
        return PointGenerator.line(center: .init(x: 0, y: 35), maxLength: 650, maxDistanceBetweenPoints: .init(x: 160, y: 0)).generate(count: gameRoom.players.count).map({ CGPoint(x: Double($0.position.x), y: Double($0.position.y)) })
    }
    
    // MARK: - Handles
    
    private func getGameRoom(data: GameRoom.GetGameRoomResponse) {
        gameRoom = GameRoomModel(id: data.gameRoom.id, name: data.gameRoom.name, hasStarted: data.gameRoom.hasStarted, isRemovable: data.gameRoom.isRemovable, hasEnded: data.gameRoom.hasEnded, players: data.gameRoom.players.map({ .init(user: $0.user, status: $0.status, localizedPlayer: LocalizedPlayer(savedPlayer: $0.savedPlayer, savedPlayers: data.gameRoom.players.compactMap({ $0.savedPlayer }))) }), observers: data.gameRoom.observers)
        optionsVersion = data.version
        options = Data(data.options.utf8)
        titleLabel.string = gameRoom.hasStarted ? gameRoom.name : NSLocalizedString("menu.game.new", bundle: .boardGameKit, value: "New Game", comment: "")
        if gameRoom.hasStarted {
            summaryView = createSummaryView()
            if gameRoom.hasEnded {
                let exportButton = ImageButton2D(systemName: "square.and.arrow.up.circle")
                exportButton.tap = { [unowned self] _ in
                    send(GameRoom.GetGameArchiveRequest())
                }
                exportButton.position = CGPoint(x: titleLabel.calculateAccumulatedFrame().maxX + 60, y: 0)
                titleLabel.parent!.addChild(exportButton)
                startButton.string = NSLocalizedString("menu.game.reopen", bundle: .boardGameKit, value: "Open", comment: "")
            } else {
                if gameRoom.isRemovable {
                    let removeButton = ImageButton2D(systemName: "trash.circle", color: .systemRed)
                    removeButton.tap = { [unowned self] _ in
                        send(GameRoom.RemoveGameRequest())
                        transition(to: previousScene)
                        previousScene = nil
                    }
                    removeButton.position = CGPoint(x: titleLabel.calculateAccumulatedFrame().maxX + 60, y: 0)
                    titleLabel.parent!.addChild(removeButton)
                }
                startButton.string = if gameRoom.observers.contains(id: User.local!.id) {
                    NSLocalizedString("menu.game.observe", bundle: .boardGameKit, value: "Observe", comment: "")
                } else {
                    NSLocalizedString("menu.game.rejoin", bundle: .boardGameKit, value: "Rejoin", comment: "")
                }
            }
            startButton.tap = { [unowned self] _ in
                send(GameRoom.ReconnectRequest(player: impersonatedPlayer, eventGroupId: nil))
            }
            viewType = .summary
        } else {
            playersView = GameRoomPlayersView()
            playersView!.nextButton.tap = { [unowned self] _ in
                viewType = optionsView != nil ? .options : .summary
            }
            optionsView = createOptionsView()
            summaryView = createSummaryView()
            updatePlayerCount()
            optionsView?.setOptions(Data(data.options.utf8))
            if gameRoom.observers.contains(id: User.local!.id) {
                startButton.enable(false)
                startButton.string = NSLocalizedString("menu.game.observe", bundle: .boardGameKit, value: "Observe", comment: "")
            } else {
                startButton.tap = { [unowned self] _ in
                    send(GameRoom.SetReadyRequest(optionsVersion: optionsVersion))
                    isEnabled = false
                }
                startButton.string = if GameHostShared is LocalGameHost {
                    NSLocalizedString("menu.game.start", bundle: .boardGameKit, value: "Start", comment: "")
                } else {
                    NSLocalizedString("menu.game.ready", bundle: .boardGameKit, value: "Ready", comment: "")
                }
            }
            viewType = .players
        }
    }
    
    private func joinGameRoom(data: GameRoom.JoinGameRoomResponse) {
        if gameRoom.hasStarted {
            if let player = gameRoom.players.first(where: { $0.localizedPlayer.id == data.player?.savedPlayer.id }) {
                player.status = data.player?.status
                if viewType == .summary {
                    playerViews.first(where: { $0.player === player })?.icon.setBorderColorAnimated(player.status!.color)
                }
            }
        } else if let player = data.player {
            let player = GameRoomModel.Player(user: player.user, status: player.status, localizedPlayer: LocalizedPlayer(savedPlayer: player.savedPlayer, savedPlayers: gameRoom.players.compactMap({ $0.localizedPlayer.savedPlayer })))
            gameRoom.players.append(player)
            updatePlayerCount()
            if viewType == .summary {
                let playerView = PlayerView(player: player, borderColor: player.status?.color ?? GameRoom.Status.botColor)
                playerViews.append(playerView)
                playerView.alpha = 0
                playerView.run(.fadeIn(withDuration: 0.1))
                summaryView.addChild(playerView)
                for (player, position) in zip(gameRoom.players, playerViewPositions()) {
                    playerViews.first(where: { $0.player === player })!.run(.move(to: position, duration: 0.1).withTimingMode(.easeOut))
                }
            }
        } else if let observer = data.observer {
            gameRoom.observers.append(observer)
        }
    }
    
    private func leaveGameRoom(data: GameRoom.LeaveGameRoomResponse) {
        if gameRoom.hasStarted {
            if let player = gameRoom.players.first(where: { $0.user?.id == data.user }) {
                player.status = .dropped
                if viewType == .summary {
                    playerViews.first(where: { $0.player === player })?.icon.setBorderColorAnimated(player.status!.color)
                }
            }
        } else {
            for player in gameRoom.players.filter({ ($0.user?.id ?? $0.localizedPlayer.id) == data.user || $0.localizedPlayer.savedPlayer.host == data.user }) {
                gameRoom.players.remove(at: gameRoom.players.firstIndex(where: { $0 === player })!)
                if viewType == .summary, let index = playerViews.firstIndex(where: { $0.player === player }) {
                    playerViews.remove(at: index).run(.sequence([
                        .fadeOut(withDuration: 0.1),
                        .removeFromParent()
                    ]))
                    for (player, position) in zip(gameRoom.players, playerViewPositions()) {
                        playerViews.first(where: { $0.player === player })!.run(.move(to: position, duration: 0.1).withTimingMode(.easeOut))
                    }
                }
            }
            updatePlayerCount()
            if let index = gameRoom.observers.firstIndex(id: data.user) {
                gameRoom.observers.remove(at: index)
            }
        }
    }
    
    private func statusChange(data: GameRoom.StatusChangeResponse) {
        for player in gameRoom.players.filter({ $0.localizedPlayer.id == data.player || $0.localizedPlayer.savedPlayer.host == data.player }) {
            player.status = data.status
            if viewType == .summary {
                playerViews.first(where: { $0.player === player })?.icon.setBorderColorAnimated(player.status!.color)
            }
        }
        if data.player == User.local!.id {
            isEnabled = true
            if data.status == .ready {
                backButton.enable(false)
                startButton.tap = { [unowned self] _ in
                    send(GameRoom.SetNotReadyRequest())
                    isEnabled = false
                }
                startButton.string = NSLocalizedString("menu.game.ready.not", bundle: .boardGameKit, value: "Not Ready", comment: "")
            } else {
                backButton.enable(true)
                startButton.tap = { [unowned self] _ in
                    send(GameRoom.SetReadyRequest(optionsVersion: optionsVersion))
                    isEnabled = false
                }
                startButton.string = NSLocalizedString("menu.game.ready", bundle: .boardGameKit, value: "Ready", comment: "")
                startButton.run(.sequence([
                    .scale(to: 1.5, duration: 0.1).withTimingMode(.easeOut),
                    .scale(to: 1, duration: 0.1).withTimingMode(.easeIn)
                ]))
            }
        }
    }
    
    public func setBotStrategy(data: GameRoom.SetBotStrategyRequestResponse) {
        playersView!.setBotStrategy(data: data)
    }
    
    public func sendOptions() {
        send(GameRoom.SetOptionsRequestResponse(version: optionsVersion, options: optionsView!.options.encoded()))
    }
    
    public func setOptions(data: GameRoom.SetOptionsRequestResponse) {
        optionsVersion = data.version
        options = Data(data.options.utf8)
        optionsView?.setOptions(options)
    }
    
    private func startGame(data: GameRoom.StartGameResponse) {
        GameSceneContext(gameContext: GameContext(undoManager: UndoManager()), isPhone: GameViewController.isPhone, hostPlayer: impersonatedPlayer ?? User.local?.id).makeCurrent {
            transition(to: GameOverlayScene(data: data, localizedPlayers: data.players.map({ player in gameRoom.players.first(where: { $0.localizedPlayer.id == player.id })!.localizedPlayer })))
        }
    }
    
    private func getGameArchive(data: GameManager.ArchiveGameResponse) {
        do {
            try FileSystem.shared.save(data.game, fileName: data.name)
        } catch {
            showError(error)
        }
    }
    
}

class GameRoomPlayersView: SKNode {
    
    private var totalPlayerCountBar: SKShapeNode!
    private var botCountLabel: TextNode2D!
    private var addBotButton: ImageButton2D!
    private var removeBotButton: ImageButton2D!
    private var botStrategyButton: TextButton2D!
    private var localPlayerCountLabel: TextNode2D!
    private var addDeviceClientButton: ImageButton2D!
    private var removeDeviceClientButton: ImageButton2D!
    private var remotePlayerCountLabel: TextNode2D!
    private var botStrategy = HostConfiguration.shared.botStrategies.first
    private let playerCountBarFrame = CGRect(x: -150, y: 2, width: 300, height: 10)
    private(set) var nextButton: TextButton2D!
    
    override init() {
        super.init()
        
        let subview = SKNode()
        
        let botsLabel = TextNode2D(string: NSLocalizedString("gameRoom.bots", bundle: .boardGameKit, value: "Bots:", comment: ""), horizontalAlignment: .right)
        botsLabel.position = CGPoint(x: -80, y: 90)
        subview.addChild(botsLabel)
        
        let botsView = createBotsView()
        botsView.position = CGPoint(x: 0, y: 90)
        subview.addChild(botsView)
        
        let localPlayersLabel = TextNode2D(string: NSLocalizedString("gameRoom.localPlayers", bundle: .boardGameKit, value: "Local players:", comment: ""), horizontalAlignment: .right)
        localPlayersLabel.position = CGPoint(x: -80, y: 10)
        subview.addChild(localPlayersLabel)
        
        let localPlayersView = createLocalPlayersView()
        localPlayersView.position = CGPoint(x: 0, y: 10)
        subview.addChild(localPlayersView)
        
        let remotePlayerCount = TextNode2D(string: NSLocalizedString("gameRoom.removePlayers", bundle: .boardGameKit, value: "Remote players:", comment: ""), horizontalAlignment: .right)
        remotePlayerCount.position = CGPoint(x: -80, y: -70)
        subview.addChild(remotePlayerCount)
        
        remotePlayerCountLabel = TextNode2D(string: "", horizontalAlignment: .right)
        remotePlayerCountLabel.position = CGPoint(x: 0, y: -70)
        subview.addChild(remotePlayerCountLabel)
        
        let subviewFrame = subview.calculateAccumulatedFrame()
        subview.position = CGPoint(x: -(subviewFrame.maxX + subviewFrame.minX) / 2, y: 0)
        addChild(subview)
        
        let playerCountView = createPlayerCountView()
        playerCountView.position = CGPoint(x: 0, y: -140)
        addChild(playerCountView)
        
        nextButton = TextButton2D(string: NSLocalizedString("button.next", bundle: .boardGameKit, value: "Next", comment: ""), backgroundImageIndex: 0)
        nextButton.position = CGPoint(x: 0, y: -220)
        addChild(nextButton)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func send<T: Request>(_ data: T) {
        ServerShared.send(data)
    }
    
    private func createBotsView() -> SKNode {
        let view = SKNode()
        
        botCountLabel = TextNode2D(string: "", horizontalAlignment: .right)
        botCountLabel.position = CGPoint(x: 0, y: 0)
        view.addChild(botCountLabel)
        
        let removeButton = ImageButton2D(systemName: "minus.circle")
        removeBotButton = removeButton
        removeButton.tap = { [unowned self] _ in
            send(GameRoom.RemoveBotRequest(player: players.last(where: { $0.localizedPlayer.savedPlayer.botStrategy != nil })!.localizedPlayer.id))
        }
        removeButton.position = CGPoint(x: 80, y: 15)
        view.addChild(removeButton)
        
        let addButton = ImageButton2D(systemName: "plus.circle")
        addBotButton = addButton
        addButton.tap = { [unowned self] _ in
            send(GameRoom.AddBotRequest())
        }
        addButton.position = CGPoint(x: 160, y: 15)
        view.addChild(addButton)
        
        if let botStrategy = botStrategy, case let botStrategies = HostConfiguration.shared.botStrategies, botStrategies.count > 1 {
            let strategyButton = TextButton2D(string: (botStrategy as? LocalizedLabel)?.localizedLabel ?? botStrategy.rawValue, horizontalAlignment: .left, backgroundImageIndex: 0)
            botStrategyButton = strategyButton
            strategyButton.tap = { [unowned self] _ in
                send(GameRoom.SetBotStrategyRequestResponse(strategy: HostConfiguration.shared.botStrategies[(HostConfiguration.shared.botStrategies.firstIndex(where: { $0.rawValue == self.botStrategy?.rawValue })! + 1) % botStrategies.count].rawValue))
            }
            strategyButton.position = CGPoint(x: 220, y: 0)
            view.addChild(strategyButton)
        }
        
        return view
    }
    
    private func createLocalPlayersView() -> SKNode {
        let view = SKNode()
        
        localPlayerCountLabel = TextNode2D(string: "", horizontalAlignment: .right)
        localPlayerCountLabel.position = CGPoint(x: 0, y: 0)
        view.addChild(localPlayerCountLabel)
        
        let removeButton = ImageButton2D(systemName: "minus.circle")
        removeDeviceClientButton = removeButton
        removeButton.tap = { [unowned self] _ in
            send(GameRoom.RemoveDeviceClientRequest(player: players.last(where: { $0.localizedPlayer.savedPlayer.host == User.local!.id })!.localizedPlayer.savedPlayer.id))
        }
        removeButton.position = CGPoint(x: 80, y: 15)
        view.addChild(removeButton)
        
        let addButton = ImageButton2D(systemName: "plus.circle")
        addDeviceClientButton = addButton
        addButton.tap = { [unowned self] _ in
            send(GameRoom.AddDeviceClientRequest())
        }
        addButton.position = CGPoint(x: 160, y: 15)
        view.addChild(addButton)
        
        return view
    }
    
    private func createPlayerCountView() -> SKNode {
        let view = SKNode()
        
        let playerCountBarBackground = SKShapeNode(rect: playerCountBarFrame, cornerRadius: playerCountBarFrame.height / 2)
        playerCountBarBackground.fillColor = .darkGray
        view.addChild(playerCountBarBackground)
        
        let x = (playerCountBarFrame.maxX - playerCountBarFrame.minX) / Double(HostConfiguration.shared.game.requiredPlayerCount.upperBound) * Double(HostConfiguration.shared.game.requiredPlayerCount.lowerBound)
        let minPlayerBar = SKShapeNode(rect: CGRect(origin: playerCountBarFrame.origin, size: CGSize(width: x, height: playerCountBarFrame.height)), cornerRadius: playerCountBarFrame.height / 2) // "import SceneKit" causes project compile time to increase by almost 800%
        minPlayerBar.fillColor = .clear
        view.addChild(minPlayerBar)
        
        totalPlayerCountBar = SKShapeNode()
        view.addChild(totalPlayerCountBar)
        
        let zeroPlayerCount = TextNode2D(string: 0.formatted(), fontSize: 20, horizontalAlignment: .right)
        zeroPlayerCount.position = CGPoint(x: playerCountBarFrame.minX - 8, y: 0)
        view.addChild(zeroPlayerCount)
        
        let maxPlayerCount = TextNode2D(string: HostConfiguration.shared.game.requiredPlayerCount.upperBound.formatted(), fontSize: 20, horizontalAlignment: .left)
        maxPlayerCount.position = CGPoint(x: playerCountBarFrame.maxX + 8, y: 0)
        view.addChild(maxPlayerCount)
        
        return view
    }
    
    var players = [GameRoomScene.GameRoomModel.Player]() {
        didSet {
            let fraction = playerCountBarFrame.width / Double(HostConfiguration.shared.game.requiredPlayerCount.upperBound)
            GameViewController.shared.updateSpriteKit { [totalPlayerCountBar, playerCountBarFrame, players] in
                totalPlayerCountBar!.path = CGPath(roundedRect: CGRect(origin: playerCountBarFrame.origin, size: CGSize(width: fraction * Double(players.count), height: playerCountBarFrame.height)), cornerWidth: playerCountBarFrame.height / 2, cornerHeight: playerCountBarFrame.height / 2, transform: nil) // "import SceneKit" causes project compile time to increase by almost 800%
                totalPlayerCountBar!.fillColor = HostConfiguration.shared.game.requiredPlayerCount.contains(players.count) ? .systemGreen : .systemRed
            }
            
            let botCount = players.filter({ $0.localizedPlayer.savedPlayer.botStrategy != nil }).count
            botCountLabel.string = botCount.formatted()
            addBotButton.enable(HostConfiguration.shared.game is any GameBot.Type && botStrategy != nil && players.count < HostConfiguration.shared.game.requiredPlayerCount.upperBound)
            removeBotButton.enable(botCount > 0)
            
            let deviceClientCount = players.filter({ $0.localizedPlayer.savedPlayer.host == User.local!.id }).count
            let localPlayerCount = deviceClientCount + 1
            localPlayerCountLabel.string = localPlayerCount.formatted()
            addDeviceClientButton.enable(players.count < HostConfiguration.shared.game.requiredPlayerCount.upperBound)
            removeDeviceClientButton.enable(deviceClientCount > 0)
            
            let remotePlayerCount = players.count - botCount - localPlayerCount
            remotePlayerCountLabel.string = remotePlayerCount.formatted()
            
            nextButton.enable(HostConfiguration.shared.game.requiredPlayerCount.contains(players.count))
        }
    }
    
    func setBotStrategy(data: GameRoom.SetBotStrategyRequestResponse) {
        botStrategy = HostConfiguration.shared.botStrategies.first(where: { $0.rawValue == data.strategy })!
        botStrategyButton.string = (botStrategy! as? LocalizedLabel)?.localizedLabel ?? botStrategy!.rawValue
    }
    
}

extension GameOptionsView {
    
    func setOptions(_ data: Data) {
        options = try! RequestCoder.decode(Options.self, from: data)
    }
    
}

extension GameRoom.Status {
    
    static var botColor: Color {
        .systemPurple
    }
    
    var color: Color {
        return switch self {
        case .notReady, .connecting:
            .systemOrange
        case .ready:
            .systemGreen
        case .dropped:
            .systemRed
        }
    }
    
}
