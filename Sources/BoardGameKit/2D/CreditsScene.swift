import BoardGameKitHost
import SpriteKit

public class CreditsScene: Scene2D {
    
    private var title: SKNode!
    private var credits: SKNode!
    private var versionInfo: SKNode!
    
    private let fontName = ClientConfiguration.shared.theme.creditsFontName ?? ClientConfiguration.shared.theme.labelFontName
    private let fontSize = ClientConfiguration.shared.theme.creditsFontSize
    private let color = ClientConfiguration.shared.theme.creditsTextColor ?? .white
    private let shadowColor = ClientConfiguration.shared.theme.creditsTextShadowColor ?? .clear
    
    required override init() {
        super.init()
        title = createTitle()
        addChild(title)
        credits = createCredits()
        addChild(credits)
        versionInfo = createVersionInfo()
        addChild(versionInfo)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override var frame: CGRect {
        return CGRect(x: 0, y: 0, width: 800, height: 400)
    }
    
    public override func layout() {
        super.layout()
        if GameViewController.isPhone {
            title.position = CGPoint(x: sceneFrame.minX + 50, y: sceneFrame.maxY - 50)
        } else {
            title.position = CGPoint(x: sceneFrame.minX + 100, y: sceneFrame.maxY - 100)
        }
        versionInfo.position = CGPoint(x: sceneFrame.minX + 30, y: sceneFrame.minY + 30)
    }
    
    private func createTitle() -> SKNode {
        let title = SKNode()
        
        let backButton = BackButton()
        backButton.tap = { [unowned self] _ in
            transition(to: ClientConfiguration.shared.scenes.mainMenu.init())
        }
        backButton.position = CGPoint(x: 0, y: 0)
        title.addChild(backButton)
        
        let label = TextNode2D(string: NSLocalizedString("menu.game.credits", bundle: .boardGameKit, value: "Credits", comment: ""), fontSize: 40, horizontalAlignment: .left, verticalAlignment: .center)
        label.position = CGPoint(x: 50, y: 0)
        title.addChild(label)
        
        return title
    }
    
    private func createCredits() -> SKNode {
        let view = SKNode()
        
        let credits = Credits.shared!
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let font = Font(name: fontName, size: fontSize)!
        
        if let author = credits.authorWithLabel {
            let author = TextNode2D(attributedString: NSAttributedString(string: author, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraphStyle]), verticalAlignment: .center, maxWidth: 800, shadowColor: shadowColor)
            author.position = CGPoint(x: 0, y: 100)
            view.addChild(author)
        }
        
        let row = [credits.designWithLabel, credits.publisherWithLabel, credits.developerWithLabel].compactMap({ $0 })
        for (i, credit) in row.enumerated() {
            let credit = TextNode2D(attributedString: NSAttributedString(string: credit, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraphStyle]), verticalAlignment: .center, maxWidth: 200, shadowColor: shadowColor)
            credit.position = CGPoint(x: 230 * (-Double(row.count - 1) / 2 + Double(i)), y: 0)
            view.addChild(credit)
        }
        
        if let websiteUrl = credits.websiteUrl {
            let websiteButton = TextButton2D(string: credits.websiteLabel ?? NSLocalizedString("menu.game.website", bundle: .boardGameKit, value: "Website", comment: ""), backgroundImageIndex: 0)
            websiteButton.tap = { _ in
                #if os(macOS)
                NSWorkspace.shared.open(websiteUrl)
                #else
                UIApplication.shared.open(websiteUrl)
                #endif
            }
            websiteButton.position = CGPoint(x: 0, y: (view.children.last?.calculateAccumulatedFrame().minY ?? 0) - 70) // SKLabelNode with NSAttributedString throws runtime error when accessing frame property and string is empty (FB14843924, fixed in macOS 15.4)
            view.addChild(websiteButton)
        }
        
        if let feedbackUrl = credits.feedbackUrl {
            let feedbackButton = TextButton2D(string: NSLocalizedString("menu.game.feedback", bundle: .boardGameKit, value: "Feedback", comment: ""), backgroundImageIndex: 1)
            feedbackButton.tap = { _ in
                #if os(macOS)
                NSWorkspace.shared.open(feedbackUrl)
                #else
                UIApplication.shared.open(feedbackUrl)
                #endif
            }
            feedbackButton.position = CGPoint(x: 0, y: credits.websiteUrl != nil ? (view.children.last?.position.y ?? 0) - 60 : (view.children.last?.calculateAccumulatedFrame().minY ?? 0) - 70) // SKLabelNode with NSAttributedString throws runtime error when accessing frame property and string is empty (FB14843924, fixed in macOS 15.4)
            view.addChild(feedbackButton)
        }
        
        return view
    }
    
    private func createVersionInfo() -> SKNode {
        return TextNode2D(string: "\(Bundle.main.name) \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String) (\(Bundle.main.version))", fontName: fontName, fontSize: fontSize, color: color, horizontalAlignment: .left, shadowColor: shadowColor)
    }
    
}
