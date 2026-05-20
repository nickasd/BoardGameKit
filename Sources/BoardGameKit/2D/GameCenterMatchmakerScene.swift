import BoardGameKitHost
@preconcurrency import GameKit

class GameCenterMatchmakerScene: Scene2D, GKMatchmakerViewControllerDelegate {
    
    private var title: SKNode!
    private var content: SKNode!
    private var gameCenterViewController: ViewController?
    private var matchStarted = false
    private var match: GKMatch?
    
    required override init() {
        super.init()
        title = createTitle()
        addChild(title)
        content = TextNode2D(string: NSLocalizedString("loading", bundle: .boardGameKit, value: "Loading...", comment: ""))
        addChild(content)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func willAppear() {
        addHandle(register)
    }
    
    public override func transition(to scene: Scene2D) {
        removeAllHandles()
        super.transition(to: scene)
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
    
    private func createTitle() -> SKNode {
        let title = SKNode()
        
        let backButton = BackButton()
        backButton.tap = { [unowned self] _ in
            transition(to: PlayScene())
        }
        backButton.position = CGPoint(x: 0, y: 0)
        title.addChild(backButton)
        
        let label = TextNode2D(string: NSLocalizedString("menu.game.online", bundle: .boardGameKit, value: "Online Game", comment: ""), fontSize: 40, horizontalAlignment: .left, verticalAlignment: .center)
        label.position = CGPoint(x: 50, y: 0)
        title.addChild(label)
        
        return title
    }
    
    func showMatchmaker() {
        dismiss() // when switching to another app and back again, the user is authenticated again
        let request = GKMatchRequest()
        request.minPlayers = HostConfiguration.shared.game.requiredPlayerCount.lowerBound
        request.maxPlayers = min(HostConfiguration.shared.game.requiredPlayerCount.upperBound, GKMatchRequest.maxPlayersAllowedForMatch(of: .peerToPeer))
        request.defaultNumberOfPlayers = request.minPlayers
        request.inviteMessage = "Ciao!"
        guard let viewController = GKMatchmakerViewController(matchRequest: request) else { // Going into Mission Control after presenting GKMatchmakerViewController causes window to become unresponsive (FB21325081)
            return
        }
        viewController.matchmakerDelegate = self
        present(viewController)
    }
    
    func player(_ player: GKPlayer, didAccept invite: GKInvite) {
        dismiss()
        guard let viewController = GKMatchmakerViewController(invite: invite) else {
            return
        }
        viewController.matchmakerDelegate = self
        present(viewController)
//        if let disconnectedServer = GameCenterServer.disconnectedServer {
//            Task { @MainActor in
//                let matchRequest = GKMatchRequest()
//                matchRequest.recipients = disconnectedServer.match.players
//                matchRequest.recipientResponseHandler = { player, response in
//                    Logger.shared.info("Invited player \(player.displayName) responsed \(response)")
//                }
//                do {
//                    try await GKMatchmaker.shared().addPlayers(to: disconnectedServer.match, matchRequest: matchRequest)
//                    Logger.shared.info("Sent invitation to \(player.displayName)")
//                } catch {
//                    Logger.shared.error("Invitation to \(player.displayName) failed.\n\(error.localizedDescription)")
//                }
//                ServerShared = GameCenterServer(match: disconnectedServer.match, host: disconnectedServer.host)
//                ServerShared.delegate = self
//            }
//        }
    }
    
    nonisolated func matchmakerViewControllerWasCancelled(_ viewController: GKMatchmakerViewController) {
        MainActor.assumeIsolated {
            dismiss()
            transition(to: PlayScene())
        }
    }
    
    nonisolated func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFind match: GKMatch) {
        MainActor.assumeIsolated {
            self.match = match
            startMatch()
        }
    }
    
    nonisolated func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            dismiss()
            showError(error)
            transition(to: PlayScene())
        }
    }
    
    nonisolated func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        MainActor.assumeIsolated {
            startMatch()
        }
    }
    
    nonisolated func match(_ match: GKMatch, didReceive data: Data, fromRemotePlayer player: GKPlayer) {
        preconditionFailure()
    }
    
    func startMatch() {
        let match = match!
//        let match = (match ?? GameCenterServer.disconnectedServer?.match)!
        if matchStarted || match.expectedPlayerCount > 0 {
            return
        }
        Logger.shared.info("Starting match with local player \(GKLocalPlayer.local.gamePlayerID) and remote players \(match.players.map({ $0.gamePlayerID }))")
        matchStarted = true
        let host = ([GKLocalPlayer.local] + match.players).sorted(by: { $0.gamePlayerID < $1.gamePlayerID })[0]
//        match.chooseBestHostingPlayer { [self] host in // GKMatch.chooseBestHostingPlayer(_:) always returns nil player (FB9583628)
            dismiss()
//            guard let host = host else {
//                showError(HostError(message: "Couldn't determine hosting player."))
//                return
//            }
            Logger.shared.info("Found best hosting player: \(host.gamePlayerID)")
            User.local = User(id: UUID(), name: GKLocalPlayer.local.displayName)
            ServerShared = GameCenterServer(match: match, host: host)
            ServerShared.delegate = self
            if host == GKLocalPlayer.local {
                transition(to: GameRoomScene())
                GameHostShared = GameCenterGameHost(match: match, localServer: ServerShared)
                (GameHostShared as! GameCenterGameHost).addUser(User.local!, for: GKLocalPlayer.local)
                for player in match.players {
                    (GameHostShared as! GameCenterGameHost).addUser(User(id: UUID(), name: player.displayName), for: player)
                }
            }
//        }
    }
    
    #if os(macOS)
    private func present(_ viewController: NSViewController & GKViewController) {
        gameCenterViewController = viewController
        GKDialogController.shared().parentWindow = GameViewController.shared.view.window!
        GKDialogController.shared().present(viewController)
    }

    private func dismiss() {
        if let gameCenterViewController = gameCenterViewController {
            GKDialogController.shared().dismiss(gameCenterViewController)
        }
        gameCenterViewController = nil
    }
    #else
    private func present(_ viewController: UIViewController) {
        gameCenterViewController = viewController
        GameViewController.shared.present(viewController, animated: true)
    }

    private func dismiss() {
        if let gameCenterViewController = gameCenterViewController {
            gameCenterViewController.dismiss(animated: true)
        }
        gameCenterViewController = nil
    }
    #endif
    
    private func register(data: GameCenterGameHost.RegisterResponse) {
        User.local = data.user
        transition(to: GameRoomScene())
    }
    
}
