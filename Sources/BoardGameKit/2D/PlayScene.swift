import BoardGameKitHost
import SpriteKit
import SwiftUI

public class PlayScene: Scene2D {
    
    private enum Keys {
        static let port = "port"
        static let host = "host"
    }
    
    private var title: SKNode!
    private var content: SKNode!
    
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
        addHandle(register)
        
        GameHostShared?.close()
        GameHostShared = nil
        ServerShared?.delegate = nil
        ServerShared?.disconnect()
        ServerShared = nil
    }
    
    public override func transition(to scene: Scene2D) {
        removeAllHandles()
        super.transition(to: scene)
    }
    
    public override var frame: CGRect {
        return GameViewController.isPhone ? CGRect(x: 0, y: 0, width: 800, height: 400) : CGRect(x: 0, y: 0, width: 800, height: 500)
    }
    
    public override func layout() {
        super.layout()
        if GameViewController.isPhone {
            title.position = CGPoint(x: sceneFrame.minX + 50, y: sceneFrame.maxY - 50)
        } else {
            title.position = CGPoint(x: sceneFrame.minX + 100, y: sceneFrame.maxY - 100)
        }
        content.position = CGPoint(x: 0, y: 0)
    }
    
    private func createTitle() -> SKNode {
        let title = SKNode()
        
        let backButton = BackButton()
        backButton.tap = { [unowned self] _ in
            transition(to: ClientConfiguration.shared.scenes.mainMenu.init())
        }
        backButton.position = CGPoint(x: 0, y: 0)
        title.addChild(backButton)
        
        let label = TextNode2D(string: NSLocalizedString("menu.game.play", bundle: .boardGameKit, value: "Play", comment: ""), fontSize: 40, horizontalAlignment: .left, verticalAlignment: .center)
        label.position = CGPoint(x: 50, y: 0)
        title.addChild(label)
        
        return title
    }
    
    private func createContent() -> SKNode {
        let view = SKNode()
        
        let localGameButton = TextButton2D(string: NSLocalizedString("menu.game.local", bundle: .boardGameKit, value: "Local Game", comment: ""), horizontalAlignment: .center, backgroundImageIndex: 0)
        localGameButton.tap = { [unowned self] _ in
            do {
                ServerShared = LocalServer()
                ServerShared.delegate = self
                GameHostShared = try LocalGameHost(localServer: ServerShared)
                for game in LocalGames.shared.savedGames() {
                    do {
                        try (GameHostShared as! LocalGameHost).lobby.addSavedGame(game)
                    } catch {
                        showError(error)
                    }
                }
                (GameHostShared as! LocalGameHost).registerLocalUser(User.savedLocalUser)
                transition(to: LobbyScene())
            } catch {
                showError(error)
            }
        }
        localGameButton.position = CGPoint(x: 0, y: 40)
        view.addChild(localGameButton)
        
        let gameCenterButton = TextButton2D(string: NSLocalizedString("menu.game.online", bundle: .boardGameKit, value: "Online Game", comment: ""), horizontalAlignment: .center, backgroundImageIndex: 1)
        gameCenterButton.tap = { [unowned self] _ in
            startGameCenter()
            (Scene2D.current as! GameCenterMatchmakerScene).showMatchmaker()
        }
        gameCenterButton.position = CGPoint(x: 0, y: -20)
        view.addChild(gameCenterButton)
        
        let hostCustomGameButton = TextButton2D(string: NSLocalizedString("menu.game.host", bundle: .boardGameKit, value: "Host", comment: ""), fontSize: 24, horizontalAlignment: .right, backgroundImageIndex: 2)
        hostCustomGameButton.tap = { [unowned self] _ in
            let port = UserDefaults.standard.value(forKey: Keys.port) as? Int ?? 3000
            #if os(macOS)
            let viewController = NSHostingController(rootView: HostView(port: port))
            viewController.title = NSLocalizedString("menu.game.host", bundle: .boardGameKit, value: "Host", comment: "")
            viewController.rootView.callback = { [weak self] port in
                guard let self = self else { return }
                viewController.rootView.callback = nil
                GameViewController.shared.dismiss(viewController)
                if let port = port {
                    hostCustomServer(port: port)
                }
            }
            GameViewController.shared.presentAsSheet(viewController)
            #else
            let viewController = UIHostingController(rootView: HostView(port: port))
            viewController.rootView.callback = { [weak self] port in
                guard let self = self else { return }
                viewController.rootView.callback = nil
                GameViewController.shared.dismiss(animated: true)
                if let port = port {
                    hostCustomServer(port: port)
                }
            }
            GameViewController.shared.present(viewController, animated: true)
            #endif
        }
        hostCustomGameButton.position = CGPoint(x: -5, y: -80)
        view.addChild(hostCustomGameButton)
        
        let joinCustomGameButton = TextButton2D(string: NSLocalizedString("menu.game.join", bundle: .boardGameKit, value: "Join", comment: ""), fontSize: 24, horizontalAlignment: .left, backgroundImageIndex: 3)
        joinCustomGameButton.tap = { [unowned self] _ in
            let host = UserDefaults.standard.string(forKey: Keys.host).flatMap({ URL(string: $0) }) ?? URL(string: "ws://192.168.1.1:3000")!
            #if os(macOS)
            let viewController = NSHostingController(rootView: JoinView(host: host))
            viewController.title = NSLocalizedString("menu.game.join", bundle: .boardGameKit, value: "Join", comment: "")
            viewController.rootView.callback = { [weak self] host in
                guard let self = self else { return }
                viewController.rootView.callback = nil
                GameViewController.shared.dismiss(viewController)
                if let host = host {
                    joinCustomServer(host: host)
                }
            }
            GameViewController.shared.presentAsSheet(viewController)
            #else
            let viewController = UIHostingController(rootView: JoinView(host: host))
            viewController.rootView.callback = { [weak self] host in
                guard let self = self else { return }
                viewController.rootView.callback = nil
                GameViewController.shared.dismiss(animated: true)
                if let host = host {
                    joinCustomServer(host: host)
                }
            }
            GameViewController.shared.present(viewController, animated: true)
            #endif
        }
        joinCustomGameButton.position = CGPoint(x: 5, y: -80)
        view.addChild(joinCustomGameButton)
        
        return view
    }
    
    func startGameCenter() {
        transition(to: GameCenterMatchmakerScene())
    }
    
    func hostCustomServer(port: Int) {
        do {
            UserDefaults.standard.set(port, forKey: Keys.port)
            ServerShared = LocalServer()
            ServerShared.delegate = self
            GameHostShared = try WebSocketGameHost(port: port, localServer: ServerShared)
            for game in LocalGames.shared.savedGames() {
                do {
                    try (GameHostShared as! WebSocketGameHost).lobby.addSavedGame(game)
                } catch {
                    showError(error)
                }
            }
            User.savedOnlineUser = (GameHostShared as! WebSocketGameHost).registerLocalUser(User.savedOnlineUser)
            transition(to: LobbyScene())
        } catch {
            showError(error)
        }
    }
    
    func joinCustomServer(host: URL) {
        UserDefaults.standard.set(host.absoluteString, forKey: Keys.host)
        ServerShared = WebsocketServer(url: host)
        ServerShared.delegate = self
        ServerShared.connect()
    }
    
    public override func serverDidConnect(_ server: any Server) {
        send(WebSocketGameHost.RegisterRequest(user: User.savedOnlineUser))
    }
    
    private func register(data: WebSocketGameHost.RegisterResponse) {
        User.local = data.user
        User.savedOnlineUser = data.user
        transition(to: LobbyScene())
    }
    
}

struct HostView: View {
    var callback: ((Int?) -> Void)?
    
    @State private var portString: String
    @State private var isPresentingError = false
    @State private var error: HostError?
    
    init(port: Int) {
        self.portString = String(port)
    }
    
    var body: some View {
        #if os(macOS)
        content
            .padding()
            .frame(minWidth: 350)
        #else
        NavigationView {
            content
        }
        .navigationViewStyle(.stack)
        #endif
    }
    
    private var content: some View {
        Form {
            #if os(macOS)
            TextField(NSLocalizedString("host.port", bundle: .boardGameKit, value: "Server port", comment: ""), text: $portString)
            #else
            HStack {
                Text(NSLocalizedString("host.port", bundle: .boardGameKit, value: "Server port", comment: ""))
                Spacer()
                TextField(NSLocalizedString("host.port", bundle: .boardGameKit, value: "Server port", comment: ""), text: $portString)
            }
            #endif
        }
        .navigationTitle(NSLocalizedString("menu.game.host", bundle: .boardGameKit, value: "Host", comment: ""))
        .toolbar {
            ToolbarItemGroup(placement: .confirmationAction) {
                Button(NSLocalizedString("button.ok", bundle: .boardGameKit, value: "OK", comment: "")) {
                    guard let port = Int(portString) else {
                        error = HostError(message: NSLocalizedString("host.port.invalid", bundle: .boardGameKit, value: "Invalid port.", comment: ""))
                        isPresentingError = true
                        return
                    }
                    callback?(port)
                }
                .buttonStyle(.borderedProminent)
            }
            ToolbarItemGroup(placement: .cancellationAction) {
                Button(NSLocalizedString("button.cancel", bundle: .boardGameKit, value: "Cancel", comment: "")) {
                    callback?(nil)
                }
            }
        }
        .alert(isPresented: $isPresentingError, error: error) {
        }
    }
}

struct JoinView: View {
    var callback: ((URL?) -> Void)?
    
    @State private var hostString: String
    @State private var isPresentingError = false
    @State private var error: HostError?
    
    init(host: URL) {
        self.hostString = host.absoluteString
    }
    
    var body: some View {
        #if os(macOS)
        content
            .padding()
            .frame(minWidth: 350)
        #else
        NavigationView {
            content
        }
        .navigationViewStyle(.stack)
        #endif
    }
    
    private var content: some View {
        Form {
            #if os(macOS)
            TextField(NSLocalizedString("host.url", bundle: .boardGameKit, value: "Server URL", comment: ""), text: $hostString)
            #else
            HStack {
                Text(NSLocalizedString("host.url", bundle: .boardGameKit, value: "Server URL", comment: ""))
                Spacer()
                TextField(NSLocalizedString("host.url", bundle: .boardGameKit, value: "Server URL", comment: ""), text: $hostString)
            }
            #endif
        }
        .navigationTitle(NSLocalizedString("menu.game.join", bundle: .boardGameKit, value: "Join", comment: ""))
        .toolbar {
            ToolbarItemGroup(placement: .confirmationAction) {
                Button(NSLocalizedString("button.ok", bundle: .boardGameKit, value: "OK", comment: "")) {
                    guard let host = URL(string: hostString), host.scheme == "ws" && host.host != nil && host.port != nil else {
                        error = HostError(message: NSLocalizedString("host.url.invalid", bundle: .boardGameKit, value: "URL must have the 'ws' scheme, a host and a port.", comment: ""))
                        isPresentingError = true
                        return
                    }
                    callback?(host)
                }
                .buttonStyle(.borderedProminent)
            }
            ToolbarItemGroup(placement: .cancellationAction) {
                Button(NSLocalizedString("button.cancel", bundle: .boardGameKit, value: "Cancel", comment: "")) {
                    callback?(nil)
                }
            }
        }
        .alert(isPresented: $isPresentingError, error: error) {
        }
    }
}
