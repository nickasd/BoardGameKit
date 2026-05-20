import BoardGameKitHost
import SpriteKit

class LobbyScene: Scene2D {
    
    enum ViewType {
        case root
        case loadGame
    }
    
    class GameModel: Codable {
        
        let id: UUID
        let name: String
        let hasStarted: Bool
        var users: [User]
        
        init(id: UUID, name: String, hasStarted: Bool, users: [User]) {
            self.id = id
            self.name = name
            self.hasStarted = hasStarted
            self.users = users
        }
        
    }
    
    private var title: SKNode!
    private var content: SKNode!
    private var rootView: SKNode!
    private var loadGameView: SKNode!
    private var previousGamesButton: ImageButton2D!
    private var nextGamesButton: ImageButton2D!
    private var users = [User]()
    private var games = [GameModel]()
    private let gamesPerPage = 5
    private var gamePage = 0
    
    required override init() {
        super.init()
        title = createTitle()
        addChild(title)
        content = SKNode()
        addChild(content)
        rootView = createRootView()
        content.addChild(rootView)
        loadGameView = SKNode()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func willAppear() {
        addHandle(getLobby)
        addHandle(addGame)
        addHandle(removeGame)
        addHandle(startGame)
        addHandle(enterLobby)
        addHandle(joinGame)
        addHandle(leaveGameRoom)
        addHandle(disconnect)
        
        ServerShared.delegate = self
    }
    
    public override func transition(to scene: Scene2D) {
        removeAllHandles()
        super.transition(to: scene)
    }
    
    override var frame: CGRect {
        return GameViewController.isPhone ? CGRect(x: 0, y: 0, width: 800, height: 500) : CGRect(x: 0, y: 0, width: 800, height: 600)
    }
    
    override func layout() {
        super.layout()
        if GameViewController.isPhone {
            title.position = CGPoint(x: sceneFrame.minX + 50, y: sceneFrame.maxY - 50)
        } else {
            title.position = CGPoint(x: sceneFrame.minX + 100, y: sceneFrame.maxY - 100)
        }
        content.position = CGPoint(x: 0, y: 0)
    }
    
    private var viewType = ViewType.root {
        didSet {
            content.children.last!.fadeOutAndRemoveFromParent()
            let view = switch viewType {
            case .root:
                rootView!
            case .loadGame:
                loadGameView!
            }
            content.addChildAndFadeIn(view)
        }
    }
    
    private func createTitle() -> SKNode {
        let title = SKNode()
        
        let backButton = BackButton()
        backButton.tap = { [unowned self] _ in
            switch viewType {
            case .root:
                transition(to: PlayScene())
            case .loadGame:
                viewType = .root
            }
        }
        backButton.position = CGPoint(x: 0, y: 0)
        title.addChild(backButton)
        
        let string = if GameHostShared is LocalGameHost {
            NSLocalizedString("menu.game.local", bundle: .boardGameKit, value: "Local Game", comment: "")
        } else if ServerShared is GameCenterServer {
            NSLocalizedString("menu.game.online", bundle: .boardGameKit, value: "Online Game", comment: "")
        } else if GameHostShared is WebSocketGameHost {
            NSLocalizedString("menu.game.host", bundle: .boardGameKit, value: "Host", comment: "")
        } else if ServerShared is WebsocketServer {
            NSLocalizedString("menu.game.join", bundle: .boardGameKit, value: "Join", comment: "")
        } else {
            preconditionFailure()
        }
        let label = TextNode2D(string: string, fontSize: 40, horizontalAlignment: .left, verticalAlignment: .center)
        label.position = CGPoint(x: 50, y: 0)
        title.addChild(label)
        
        return title
    }
    
    private func createRootView() -> SKNode {
        let view = SKNode()
        
        let addGameButton = TextButton2D(string: NSLocalizedString("menu.game.new", bundle: .boardGameKit, value: "New Game", comment: ""), horizontalAlignment: .center, backgroundImageIndex: 0)
        addGameButton.tap = { [unowned self] _ in
            send(Lobby.AddGameRequest())
            isEnabled = false
        }
        addGameButton.position = CGPoint(x: 0, y: 40)
        view.addChild(addGameButton)
        
        let loadGameButton = TextButton2D(string: GameHostShared is LocalGameHost ? NSLocalizedString("menu.game.load", bundle: .boardGameKit, value: "Load", comment: "") : NSLocalizedString("menu.game.join", bundle: .boardGameKit, value: "Join", comment: ""), horizontalAlignment: .center, backgroundImageIndex: 1)
        loadGameButton.tap = { [unowned self] _ in
            gamePage = 0
            reloadLoadGameView()
            viewType = .loadGame
        }
        loadGameButton.position = CGPoint(x: 0, y: -20)
        view.addChild(loadGameButton)
        
        let importGameButton = TextButton2D(string: NSLocalizedString("menu.game.import", bundle: .boardGameKit, value: "Import", comment: ""), horizontalAlignment: .center, backgroundImageIndex: 2)
        importGameButton.tap = { [unowned self] _ in
            FileSystem.shared.askForOpenUrl(ofType: SavedGame.fileExtension) { [self] url in
                guard let url = url else {
                    return
                }
                do {
                    send(Lobby.ImportGameRequest(game: try Data(contentsOf: url)))
                    isEnabled = false
                } catch {
                    showError(error)
                }
            }
        }
        importGameButton.position = CGPoint(x: 0, y: -80)
        view.addChild(importGameButton)
        
        return view
    }
    
    private func reloadLoadGameView() {
        GameViewController.shared.updateSpriteKit { [loadGameView = loadGameView!] in
            loadGameView.removeAllChildren()
        }
        gamePage = min(gamePage, max(0, games.count - 1) / gamesPerPage)
        if games.isEmpty {
            GameViewController.shared.updateSpriteKit { [loadGameView = loadGameView!] in
                let label = TextNode2D(string: NSLocalizedString("empty", bundle: .boardGameKit, value: "Empty", comment: ""), horizontalAlignment: .center)
                label.position = CGPoint(x: 0, y: -60)
                loadGameView.addChild(label)
            }
        } else {
            if games.count > gamesPerPage {
                previousGamesButton = ImageButton2D(systemName: "arrow.uturn.backward.circle")
                previousGamesButton.tap = { [unowned self] _ in
                    setGamePage(gamePage - 1)
                }
                nextGamesButton = ImageButton2D(systemName: "arrow.uturn.forward.circle")
                nextGamesButton.tap = { [unowned self] _ in
                    setGamePage(gamePage + 1)
                }
                GameViewController.shared.updateSpriteKit { [previousGamesButton = previousGamesButton!, gamePage, gamesPerPage, loadGameView = loadGameView!, nextGamesButton = nextGamesButton!, games] in
                    previousGamesButton.enable(gamePage > 0)
                    previousGamesButton.position = CGPoint(x: -40, y: -Double(gamesPerPage) * 60 - 70)
                    loadGameView.addChild(previousGamesButton)
                    
                    nextGamesButton.enable(gamePage < max(0, games.count - 1) / gamesPerPage)
                    nextGamesButton.position = CGPoint(x: 40, y: -Double(gamesPerPage) * 60 - 70)
                    loadGameView.addChild(nextGamesButton)
                }
            }
            
            let page = createGamePage(at: gamePage)
            GameViewController.shared.updateSpriteKit { [loadGameView = loadGameView!] in
                loadGameView.addChild(page)
            }
        }
        GameViewController.shared.updateSpriteKit { [loadGameView = loadGameView!] in
            loadGameView.position = CGPoint(x: 0, y: loadGameView.calculateAccumulatedFrame().height / 2)
        }
    }
    
    private func createGamePage(at gamePage: Int) -> SKNode {
        let pageView = SKNode()
        for (i, game) in games[(gamePage * gamesPerPage)..<min(games.count, (gamePage + 1) * gamesPerPage)].enumerated() {
            let gameButton = TextButton2D(string: game.name, horizontalAlignment: .center, backgroundImageIndex: i)
            gameButton.tap = { [unowned self] _ in
                send(Lobby.JoinGameRequest(game: game.id))
                isEnabled = false
            }
            gameButton.position = CGPoint(x: 0, y: -Double(i + 1) * 60)
            pageView.addChild(gameButton)
        }
        pageView.position = CGPoint(x: 0, y: 0)
        return pageView
    }
    
    private func setGamePage(_ gamePage: Int) {
        loadGameView.children.last!.fadeOutAndRemoveFromParent()
        self.gamePage = gamePage
        previousGamesButton.enable(gamePage > 0)
        nextGamesButton.enable(gamePage < max(0, games.count - 1) / gamesPerPage)
        loadGameView.addChildAndFadeIn(createGamePage(at: gamePage))
    }
    
    // MARK: - Handles
    
    private func getLobby(data: Lobby.GetLobbyResponse) {
        users = data.users
        games = data.games.map({ .init(id: $0.id, name: $0.name, hasStarted: $0.hasStarted, users: $0.users) })
        if viewType == .loadGame {
            reloadLoadGameView()
        }
    }
    
    private func addGame(data: Lobby.AddGameResponse) {
        games.append(.init(id: data.game.id, name: data.game.name, hasStarted: data.game.hasStarted, users: data.game.users))
        if viewType == .loadGame {
            reloadLoadGameView()
        }
    }

    private func removeGame(data: Lobby.RemoveGameResponse) {
        games.remove(at: games.firstIndex(where: { $0.id == data.game })!)
        if viewType == .loadGame {
            reloadLoadGameView()
        }
    }

    private func startGame(data: GameRoom.StartGameResponse) {
        if viewType == .loadGame {
            reloadLoadGameView()
        }
    }
    
    private func enterLobby(data: Lobby.EnterLobbyResponse) {
        users.append(data.user)
    }
    
    private func joinGame(data: Lobby.JoinGameResponse) {
        let user = users.remove(at: users.firstIndex(id: data.user)!)
        let game = games.first(where: { $0.id == data.game })!
        if user.id == User.local?.id {
            transition(to: GameRoomScene())
        } else {
            game.users.append(.init(id: user.id, name: user.name))
        }
    }

    private func leaveGameRoom(data: GameRoom.LeaveGameRoomResponse) {
        let game = games.first(where: { $0.users.contains(where: { $0.id == data.user }) })!
        users.append(game.users.remove(at: game.users.firstIndex(id: data.user)!))
    }

    private func disconnect(data: Lobby.DisconnectResponse) {
        if let game = games.first(where: { $0.users.contains(where: { $0.id == data.user }) }) {
            game.users.remove(at: game.users.firstIndex(id: data.user)!)
        } else {
            users.remove(at: users.firstIndex(id: data.user)!)
        }
    }
    
}
