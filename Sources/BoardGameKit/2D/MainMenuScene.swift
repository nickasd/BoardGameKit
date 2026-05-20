import BoardGameKitHost
import SpriteKit

open class MainMenuScene: Scene2D {
    
    private static var background: (node: SKNode, size: CGSize)?
    
    open class func setBackground(_ background: SKNode?, size: CGSize) {
        let oldBackground = MainMenuScene.background?.node
        if let background = background {
            background.zPosition = -10
            if oldBackground == nil {
                background.alpha = 0
                background.run(.fadeIn(withDuration: 0.2))
            }
            (GameViewController.shared.scnView?.overlaySKScene ?? GameViewController.shared.skView?.scene)!.insertChild(background, at: 0)
        }
        oldBackground?.zPosition = -9
        oldBackground?.run(.sequence([
            .fadeOut(withDuration: 0.2),
            .run {
                Task { @MainActor in
                    oldBackground!.removeFromParent() // SKAction.removeFromParent() causes crash when run in SCNView.overlaySKScene (FB15498049)
                }
            }
        ]))
        #if os(macOS)
        GameViewController.shared.scnView?.needsDisplay = true // SceneKit overlay view is not drawn until performing scroll gesture (FB14155213)
        #else
        GameViewController.shared.scnView?.setNeedsDisplay() // SceneKit overlay view is not drawn until performing scroll gesture (FB14155213)
        #endif
        MainMenuScene.background = background.map({ ($0, size) })
        ClientConfiguration.shared.scenes.mainMenu.layout()
    }
    
    open class func layout() {
        guard let background = MainMenuScene.background else {
            return
        }
        background.node.setScale(max(Scene2D.current.viewFrame.width / background.size.width, Scene2D.current.viewFrame.height / background.size.height))
    }
    
    private var title: SKNode!
    private var playButton: SKNode!
    private var otherButtons: SKNode!
    
    public required override init() {
        super.init()
        if let defaultScreenBackgroundImagePath = ClientConfiguration.shared.theme.defaultScreenBackgroundImagePath {
            let texture = PreparedResources.texture(named: defaultScreenBackgroundImagePath)
            MainMenuScene.setBackground(SKSpriteNode(texture: texture), size: texture.size())
        }
        title = createTitle()
        addChild(title)
        playButton = createPlayButton()
        addChild(playButton)
        otherButtons = createOtherButtons()
        addChild(otherButtons)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func willAppear() {
        GameHostShared?.close()
        GameHostShared = nil
        ServerShared?.delegate = nil
        ServerShared?.disconnect()
//        GameCenterServer.disconnectedServer = ServerShared as? GameCenterServer
        ServerShared = nil
    }
    
    open override var frame: CGRect {
        return GameViewController.isPhone ? CGRect(x: 0, y: 0, width: 800, height: 500) : CGRect(x: 0, y: 0, width: 800, height: 700)
    }
    
    open override func layout() {
        super.layout()
        if GameViewController.isPhone {
            title.position = CGPoint(x: sceneFrame.minX + 50, y: sceneFrame.maxY - 30 - title.calculateAccumulatedFrame().height)
            playButton.position = CGPoint(x: sceneFrame.minX + 50, y: title.position.y - 80)
            otherButtons.position = CGPoint(x: sceneFrame.minX + 50, y: title.position.y - 160)
        } else {
            title.position = CGPoint(x: sceneFrame.minX + 100, y: sceneFrame.maxY - 100 - title.calculateAccumulatedFrame().height)
            playButton.position = CGPoint(x: sceneFrame.minX + 100, y: title.position.y - 120)
            otherButtons.position = CGPoint(x: sceneFrame.minX + 100, y: title.position.y - 210)
        }
        positionOtherButtons()
    }
    
    private func positionOtherButtons() {
        for (i, button) in otherButtons.children.enumerated() {
            button.position = CGPoint(x: 0, y: -Double(i) * 60)
        }
    }
    
    private func createTitle() -> SKNode {
        let maxTitleSize = CGSize(width: 600, height: 150)
        if let titleImagePath = ClientConfiguration.shared.theme.titleImagePath {
            let texture = PreparedResources.texture(named: titleImagePath)
            let ratio = min(maxTitleSize.width / texture.size().width, maxTitleSize.height / texture.size().height)
            let title = SKShapeNode(rect: CGRect(x: 0, y: 0, width: texture.size().width * ratio, height: texture.size().height * ratio), cornerRadius: 20)
            title.fillTexture = texture
            title.fillColor = .white
            title.lineWidth = 0
            return title
        } else {
            return TextNode2D(string: Bundle.main.name, fontName: ClientConfiguration.shared.theme.titleFontName ?? ClientConfiguration.shared.theme.labelFontName, fontSize: ClientConfiguration.shared.theme.titleFontSize, horizontalAlignment: .left)
        }
    }
    
    private func createPlayButton() -> SKNode {
        let playButton = TextButton2D(string: NSLocalizedString("menu.game.play", bundle: .boardGameKit, value: "Play", comment: ""), fontSize: 40, horizontalAlignment: .left, backgroundImageIndex: 0)
        playButton.tap = { [unowned self] _ in
            transition(to: PlayScene())
        }
        playButton.position = CGPoint(x: 0, y: 0)
        return playButton
    }
    
    private func createOtherButtons() -> SKNode {
        let view = SKNode()
        
        let rulesButton = TextButton2D(string: NSLocalizedString("menu.game.rules", bundle: .boardGameKit, value: "Rules", comment: ""), horizontalAlignment: .left, backgroundImageIndex: 1)
        rulesButton.tap = { [unowned self] _ in
            transition(to: HelpScene())
        }
        rulesButton.enable(ClientConfiguration.shared.scenes.rules != nil)
        view.addChild(rulesButton)
        
        let archiveButton = TextButton2D(string: NSLocalizedString("menu.game.archive", bundle: .boardGameKit, value: "Archive", comment: ""), horizontalAlignment: .left, backgroundImageIndex: 2)
        archiveButton.tap = { [unowned self] _ in
            transition(to: ArchiveScene())
        }
        view.addChild(archiveButton)
        
        let creditsButton = TextButton2D(string: NSLocalizedString("menu.game.credits", bundle: .boardGameKit, value: "Credits", comment: ""), horizontalAlignment: .left, backgroundImageIndex: 3)
        creditsButton.tap = { [unowned self] _ in
            transition(to: CreditsScene())
        }
        view.addChild(creditsButton)
        
        return view
    }
    
    public func addMenuItem(_ button: TextButton2D) {
        otherButtons.addChild(button)
        positionOtherButtons()
    }
    
    public override func serverDidDisconnect(_ server: any Server) {
        let dialog = SKNode()
        let label = TextNode2D(string: NSLocalizedString("error.lostConnection", bundle: .boardGameKit, value: "Lost connection to server", comment: ""))
        let background = SKShapeNode(rect: label.calculateAccumulatedFrame().insetBy(dx: -15, dy: -10), cornerRadius: 20)
        background.fillColor = .systemYellow.withAlphaComponent(0.8)
        background.lineWidth = 0
        dialog.addChild(background)
        dialog.addChild(label)
        dialog.zPosition = 1
        dialog.run(.sequence([
            .fadeIn(withDuration: 0.5),
            .wait(forDuration: 3),
            .fadeOut(withDuration: 0.5),
            .removeFromParent() // SKAction.removeFromParent() causes crash when run in SCNView.overlaySKScene (FB15498049)
        ]))
        addChild(dialog)
    }
        
}
