import BoardGameKitHost
import SpriteKit

public class ArchiveScene: Scene2D {
    
    private var title: SKNode!
    private var content: SKNode!
    private var previousButton: ImageButton2D!
    private var nextButton: ImageButton2D!
    private let games = LocalGames.shared.archivedGames()
    private let gamesPerPage = 5
    private var page = 0
    
    required override init() {
        super.init()
        title = createTitle()
        addChild(title)
        content = createContent()
        addChild(content)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func willAppear() {
        GameHostShared?.close()
        GameHostShared = nil
        ServerShared?.delegate = nil
        ServerShared?.disconnect()
        ServerShared = nil
        
        addHandle(getLobby)
        addHandle(addGame)
        addHandle(joinGame)
    }
    
    public override func transition(to scene: Scene2D) {
        removeAllHandles()
        super.transition(to: scene)
    }
    
    public override var frame: CGRect {
        return GameViewController.isPhone ? CGRect(x: 0, y: 0, width: 800, height: 500) : CGRect(x: 0, y: 0, width: 800, height: 600)
    }
    
    public override func layout() {
        super.layout()
        title.position = if GameViewController.isPhone {
            CGPoint(x: sceneFrame.minX + 50, y: sceneFrame.maxY - 50)
        } else {
            CGPoint(x: sceneFrame.minX + 100, y: sceneFrame.maxY - 100)
        }
        content.position = CGPoint(x: 0, y: content.calculateAccumulatedFrame().height / 2)
    }
    
    private func createTitle() -> SKNode {
        let title = SKNode()
        
        let backButton = BackButton()
        backButton.tap = { [unowned self] _ in
            transition(to: ClientConfiguration.shared.scenes.mainMenu.init())
        }
        backButton.position = CGPoint(x: 0, y: 0)
        title.addChild(backButton)
        
        let label = TextNode2D(string: NSLocalizedString("menu.game.archive", bundle: .boardGameKit, value: "Archive", comment: ""), fontSize: 40, horizontalAlignment: .left, verticalAlignment: .center)
        label.position = CGPoint(x: 50, y: 0)
        title.addChild(label)
        
        return title
    }
    
    private func createContent() -> SKNode {
        let view = SKNode()
        
        if games.isEmpty {
            let label = TextNode2D(string: NSLocalizedString("empty", bundle: .boardGameKit, value: "Empty", comment: ""), horizontalAlignment: .center)
            label.position = CGPoint(x: 0, y: -60)
            view.addChild(label)
        } else {
            if games.count > gamesPerPage {
                previousButton = ImageButton2D(systemName: "arrow.uturn.backward.circle")
                previousButton.tap = { [unowned self] _ in
                    setPage(page - 1)
                }
                previousButton.enable(false)
                previousButton.position = CGPoint(x: -40, y: -Double(gamesPerPage) * 60 - 70)
                view.addChild(previousButton)
                
                nextButton = ImageButton2D(systemName: "arrow.uturn.forward.circle")
                nextButton.tap = { [unowned self] _ in
                    setPage(page + 1)
                }
                nextButton.position = CGPoint(x: 40, y: -Double(gamesPerPage) * 60 - 70)
                view.addChild(nextButton)
            }
            
            view.addChild(createGamePage(at: page))
        }
        
        return view
    }
    
    private func createGamePage(at index: Int) -> SKNode {
        let pageView = SKNode()
        for (i, url) in games[(page * gamesPerPage)..<min(games.count, (page + 1) * gamesPerPage)].enumerated() {
            let name = (try? SavedGame.nameFormatStyle().parse(LocalGames.shared.name(fromUrl: url)).formatted(date: .long, time: .shortened)) ?? url.lastPathComponent
            let gameButton = TextButton2D(string: name, horizontalAlignment: .center, backgroundImageIndex: i)
            gameButton.tap = { [unowned self] _ in
                openGame(at: url, name: name)
            }
            gameButton.position = CGPoint(x: 0, y: -Double(i + 1) * 60)
            pageView.addChild(gameButton)
        }
        pageView.position = CGPoint(x: 0, y: 0)
        return pageView
    }
    
    private func openGame(at url: URL, name: String) {
        do {
            ServerShared = LocalServer()
            ServerShared.delegate = self
            let gameHost = try LocalGameHost(localServer: ServerShared)
            GameHostShared = gameHost
            try gameHost.lobby.addSavedGame(url)
            gameHost.registerLocalUser(User.savedLocalUser)
            ServerShared.send(Lobby.JoinGameRequest(game: gameHost.lobby.gameRooms[0].id))
        } catch {
            showError(error)
        }
    }
    
    private func setPage(_ page: Int) {
        content.children.last!.fadeOutAndRemoveFromParent()
        self.page = page
        previousButton.enable(page > 0)
        nextButton.enable(page < max(0, games.count - 1) / gamesPerPage)
        content.addChildAndFadeIn(createGamePage(at: page))
    }
    
    // MARK: - Handles
    
    private func getLobby(data: Lobby.GetLobbyResponse) {
    }
    
    private func addGame(data: Lobby.AddGameResponse) {
    }

    private func joinGame(data: Lobby.JoinGameResponse) {
        transition(to: GameRoomScene())
    }
    
}
