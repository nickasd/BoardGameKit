import SpriteKit

class LaunchScene: Scene2D {
    
    required override init() {
        super.init()
        Task {
            let clientConfiguration = ClientConfiguration.shared!
            let theme = clientConfiguration.theme
            if let launchScreenBackgroundColor = theme.launchScreenBackgroundColor {
                let fillColor = SKShapeNode(rectOf: CGSize(width: 9999, height: 9999))
                fillColor.fillColor = launchScreenBackgroundColor
                clientConfiguration.scenes.mainMenu.setBackground(fillColor, size: CGSize(width: 9999, height: 9999))
            }
            if let backgroundImagePath = theme.launchScreenBackgroundImagePath {
                try await PreparedResources.load([.init(paths: [backgroundImagePath], options: .loadTextures)])
                let texture = PreparedResources.texture(named: backgroundImagePath)
                clientConfiguration.scenes.mainMenu.setBackground(SKSpriteNode(texture: texture), size: texture.size())
            } else {
                addChild(TextNode2D(string: NSLocalizedString("loading", bundle: .boardGameKit, value: "Loading...", comment: "")))
            }
            do {
                try await PreparedResources.load(clientConfiguration.prepareResources + [.init(paths: ([clientConfiguration.playerIconsPath, clientConfiguration.floorImagePath, theme.defaultScreenBackgroundImagePath, theme.titleImagePath] + theme.textButtonBackgroundPaths + [theme.imageButtonBackgroundPath, theme.imageButtonAlternateBackgroundPath, theme.backButtonBackgroundPath]).compactMap({ $0 }), options: .loadTextures)])
            } catch {
                preconditionFailure(error.localizedDescription)
            }
            
            GameViewController.shared.updateFloor()
            await Task.yield() // allow the floor to update
            
            switch ClientConfiguration.shared.scenes.game {
            case .scene3D:
                Scene3D.current.transition(to: MainScene())
            case .scene2D:
                Scene2D.current.transition(to: ClientConfiguration.shared.scenes.mainMenu.init())
            }
            
            GameViewController.shared.registerGameCenter()
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
