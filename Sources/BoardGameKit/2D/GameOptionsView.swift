import BoardGameKitHost
import SpriteKit

@MainActor public protocol GameOptionsView: SKNode {
    associatedtype Options: GameOptions
    
    var options: Options { get set }
    var gameRoomScene: GameRoomScene! { get set }
    init()
    /// This method is called when the number of players changes.
    func updatePlayers()
}

extension GameOptionsView {
    
    public func sendOptions() {
        gameRoomScene.sendOptions()
    }
    
}

public protocol GameVariant: RawRepresentable, CaseIterable, Equatable, LocalizedLabel where RawValue == String, AllCases == [AllCases.Element] {
}

extension GameVariant {
    
    public var localizedLabel: String {
        return rawValue
    }
    
}

public protocol GameOptionsWithVariant: GameOptions {
    associatedtype Variant: GameVariant
    
    var gameVariant: Variant { get set }
}

public class VariantsGameOptionsView<Options: GameOptionsWithVariant>: SKNode, GameOptionsView {
    
    public var options = Options() {
        didSet {
            updateGameVariants()
        }
    }
    public weak var gameRoomScene: GameRoomScene!
    
    private var variantsView: SKNode!
    private var previousButton: ImageButton2D!
    private var nextButton: ImageButton2D!
    private let gameVariants = Options.Variant.allCases
    private let gameVariantsPerPage = 7
    private var page = 0
    
    required public override init() {
        super.init()
        variantsView = SKNode()
        if gameVariants.count > gameVariantsPerPage {
            previousButton = ImageButton2D(systemName: "arrow.uturn.backward.circle")
            previousButton.tap = { [unowned self] _ in
                setPage(page - 1)
            }
            previousButton.enable(false)
            previousButton.position = CGPoint(x: -40, y: -130)
            variantsView.addChild(previousButton)
            
            nextButton = ImageButton2D(systemName: "arrow.uturn.forward.circle")
            nextButton.tap = { [unowned self] _ in
                setPage(page + 1)
            }
            nextButton.position = CGPoint(x: 40, y: -130)
            variantsView.addChild(nextButton)
        }
        
        variantsView.addChild(createGamePage(at: page))
        addChild(variantsView)
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func createGamePage(at index: Int) -> SKNode {
        let pageView = SKNode()
        for (i, gameVariant) in gameVariants[(page * gameVariantsPerPage)..<min(gameVariants.count, (page + 1) * gameVariantsPerPage)].enumerated() {
            let gameVariantButton = TextButton2D(string: gameVariant.localizedLabel, backgroundImageIndex: i)
            gameVariantButton.tap = { [self] _ in
                options.gameVariant = gameVariant
                sendOptions()
            }
            gameVariantButton.position = CGPoint(x: 0, y: 360 - Double(i + 1) * 60)
            pageView.addChild(gameVariantButton)
            
            if options.gameVariant == gameVariant {
                let marker = SKShapeNode(ellipseOf: CGSize(width: 20, height: 20))
                marker.fillColor = .systemBlue
                marker.lineWidth = 0
                marker.position = CGPoint(x: gameVariantButton.calculateAccumulatedFrame().minX - 20, y: gameVariantButton.position.y + 10)
                pageView.addChild(marker)
            }
        }
        return pageView
    }
    
    private func setPage(_ page: Int) {
        variantsView.children.last!.fadeOutAndRemoveFromParent()
        self.page = page
        previousButton.enable(page > 0)
        nextButton.enable(page < max(0, gameVariants.count - 1) / gameVariantsPerPage)
        variantsView.addChildAndFadeIn(createGamePage(at: page))
    }
    
    private func updateGameVariants() {
        variantsView.children.last!.removeFromParent()
        variantsView.addChild(createGamePage(at: page))
    }
    
    public func updatePlayers() {
    }
    
}
