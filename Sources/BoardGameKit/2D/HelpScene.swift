import SpriteKit

public class HelpScene: Scene2D {
    
    private var previousScene: Scene2D!
    private var background: SKShapeNode!
    private var closeButton: ImageButton2D!
    private var progressView: SKNode!
    private var previousButton: ImageButton2D!
    private var nextButton: ImageButton2D!
    private var progressLabel: TextNode2D!
    private var rulesView: SKNode!
    private var pageViews = [SKNode]()
    private var page = 0
    
    required override init() {
        super.init()
        background = SKShapeNode()
        background.fillColor = Color(white: 0.2, alpha: 0.95)
        background.lineWidth = 0
        addChild(background)
        
        progressView = SKNode()
        addChild(progressView)
        
        closeButton = ImageButton2D(systemName: "xmark.circle")
        closeButton.tap = { [unowned self] _ in
            transition(to: previousScene)
            previousScene = nil
        }
        closeButton.position = CGPoint(x: 0, y: 0)
        addChild(closeButton)
        
        previousButton = ImageButton2D(systemName: "arrow.uturn.backward.circle")
        previousButton.tap = { [unowned self] _ in
            setPage(page - 1)
        }
        previousButton.position = CGPoint(x: -100, y: 0)
        progressView.addChild(previousButton)
        
        progressLabel = TextNode2D(string: "", fontSize: 20, verticalAlignment: .center)
        progressLabel.position = CGPoint(x: 0, y: 0)
        progressView.addChild(progressLabel)
        
        nextButton = ImageButton2D(systemName: "arrow.uturn.forward.circle")
        nextButton.tap = { [unowned self] _ in
            setPage(page + 1)
        }
        nextButton.position = CGPoint(x: 100, y: 0)
        progressView.addChild(nextButton)
        
        rulesView = ClientConfiguration.shared.scenes.rules!.init()
        pageViews = rulesView.children
        rulesView.removeAllChildren()
        addChild(rulesView)
        
        setPage(0)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override var frame: CGRect {
        return CGRect(x: 0, y: 0, width: 800, height: 600)
    }
    
    public override func willAppear() {
        previousScene = Scene2D.current
    }
    
    public override func layout() {
        super.layout()
        background.path = CGPath(rect: unsafeSceneFrame, transform: nil)
        closeButton.position = CGPoint(x: sceneFrame.maxX - 50, y: sceneFrame.maxY - 50)
        progressView.position = CGPoint(x: 0, y: sceneFrame.maxY - 50)
        rulesView.position = CGPoint(x: 0, y: -50)
    }
    
    private func setPage(_ page: Int) {
        pageViews[self.page].fadeOutAndRemoveFromParent()
        self.page = page
        progressLabel.string = "\((page + 1).formatted()) / \(pageViews.count.formatted())"
        previousButton.enable(page > 0)
        nextButton.enable(page < pageViews.count - 1)
        rulesView.addChildAndFadeIn(pageViews[page])
    }
    
}
