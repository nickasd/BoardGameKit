import SpriteKit
import CoreImage.CIFilterBuiltins

public class TextNode2D: SKNode {
    
    private let label: SKLabelNode
    private let shadow: SKLabelNode
    
    public init(string: String, fontName: String = ClientConfiguration.shared.theme.labelFontName, fontSize: Double = ClientConfiguration.shared.theme.labelBaseFontSize, color: Color = .white, horizontalAlignment: SKLabelHorizontalAlignmentMode = .center, verticalAlignment: SKLabelVerticalAlignmentMode = .baseline, maxWidth: Double = 0, shadowColor: Color? = nil) {
        let fontSize = ClientConfiguration.shared.theme.labelFontSize(for: fontSize)
        label = SKLabelNode(text: string)
        label.fontName = fontName
        label.fontSize = fontSize
        label.fontColor = color
        label.horizontalAlignmentMode = horizontalAlignment
        label.verticalAlignmentMode = verticalAlignment
        if maxWidth > 0 {
            label.numberOfLines = 0
            label.lineBreakMode = .byWordWrapping
            label.preferredMaxLayoutWidth = maxWidth
        }
        
        shadow = SKLabelNode(text: string)
        shadow.fontName = fontName
        shadow.fontSize = fontSize
        shadow.fontColor = shadowColor ?? .black.withAlphaComponent(0.9)
        shadow.horizontalAlignmentMode = horizontalAlignment
        shadow.verticalAlignmentMode = verticalAlignment
        if maxWidth > 0 {
            shadow.numberOfLines = 0
            shadow.lineBreakMode = .byWordWrapping
            shadow.preferredMaxLayoutWidth = maxWidth
        }
        
        super.init()
        if let shadowColor = shadowColor {
            if shadowColor != .clear {
                addChild(SKEffectNode(shadow: shadow))
            }
        } else {
            shadow.position = CGPoint(x: 1, y: -1)
            addChild(shadow)
        }
        addChild(label)
    }
    
    public init(attributedString: NSAttributedString, verticalAlignment: SKLabelVerticalAlignmentMode = .baseline, maxWidth: Double = 0, shadowColor: Color? = nil) {
        label = SKLabelNode(attributedText: attributedString)
        label.verticalAlignmentMode = verticalAlignment
        label.numberOfLines = 0
        if maxWidth > 0 {
            label.lineBreakMode = .byWordWrapping
            label.preferredMaxLayoutWidth = maxWidth
        }
        
        let shadowAttributedString = NSMutableAttributedString(attributedString: attributedString)
        shadowAttributedString.addAttribute(.foregroundColor, value: shadowColor ?? .black.withAlphaComponent(0.9), range: NSRange(location: 0, length: shadowAttributedString.length))
        shadow = SKLabelNode(attributedText: shadowAttributedString)
        shadow.verticalAlignmentMode = verticalAlignment
        shadow.numberOfLines = 0
        if maxWidth > 0 {
            shadow.lineBreakMode = .byWordWrapping
            shadow.preferredMaxLayoutWidth = maxWidth
        }
        
        super.init()
        if let shadowColor = shadowColor {
            if shadowColor != .clear {
                addChild(SKEffectNode(shadow: shadow))
            }
        } else {
            shadow.position = CGPoint(x: 1, y: -1)
            addChild(shadow)
        }
        addChild(label)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public var string: String {
        get {
            return label.text!
        }
        set {
            label.text = newValue
            shadow.text = newValue
        }
    }
    
    var numberOfLines: Int {
        get {
            return label.numberOfLines
        }
        set {
            label.numberOfLines = newValue
            shadow.numberOfLines = newValue
        }
    }
    
}

public class TextButton2D: ButtonNode2D {
    
    private let horizontalAlignment: SKLabelHorizontalAlignmentMode
    private let background: SKShapeNode
    private let backgroundImageIndex: Int
    private let label: SKLabelNode
    private let shadow: SKLabelNode
    
    public init(string: String, fontName: String = ClientConfiguration.shared.theme.labelFontName, fontSize: Double = ClientConfiguration.shared.theme.labelBaseFontSize, horizontalAlignment: SKLabelHorizontalAlignmentMode = .center, backgroundImageIndex: Int = 0) {
        self.horizontalAlignment = horizontalAlignment
        
        let fontSize = ClientConfiguration.shared.theme.labelFontSize(for: fontSize)
        background = SKShapeNode()
        self.backgroundImageIndex = backgroundImageIndex
        
        label = SKLabelNode(text: string)
        label.fontName = fontName
        label.fontSize = fontSize
        label.fontColor = .white
        
        shadow = SKLabelNode(text: string)
        shadow.fontName = fontName
        shadow.fontSize = fontSize
        shadow.fontColor = .black
        shadow.position = CGPoint(x: 1, y: -1)
        
        super.init()
        addChild(background)
        addChild(shadow)
        addChild(label)
        updateBackground()
    }
    
    public init(attributedString: NSAttributedString, horizontalAlignment: SKLabelHorizontalAlignmentMode = .center, backgroundImageIndex: Int = 0) {
        self.horizontalAlignment = horizontalAlignment
        
        background = SKShapeNode()
        self.backgroundImageIndex = backgroundImageIndex
        
        label = SKLabelNode(attributedText: attributedString)
        
        let shadowAttributedString = NSMutableAttributedString(attributedString: attributedString)
        shadowAttributedString.addAttribute(.foregroundColor, value: Color.black.withAlphaComponent(0.9), range: NSRange(location: 0, length: shadowAttributedString.length))
        shadow = SKLabelNode(attributedText: shadowAttributedString)
        
        super.init()
        addChild(background)
        addChild(shadow)
        addChild(label)
        updateBackground()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public var minWidth = 0.0 {
        didSet {
            GameViewController.shared.updateSpriteKit { [self] in
                updateBackground()
            }
        }
    }
    
    public var string: String {
        get {
            return label.text!
        }
        set {
            GameViewController.shared.updateSpriteKit { [self] in
                label.text = newValue
                shadow.text = newValue
                updateBackground()
            }
        }
    }
    
    private func updateBackground() {
        var imageData: Data?
        if case let textButtonBackgroundPaths = ClientConfiguration.shared.theme.textButtonBackgroundPaths, !textButtonBackgroundPaths.isEmpty {
            imageData = try! Data(contentsOf: Bundle.main.url(forResource: textButtonBackgroundPaths[backgroundImageIndex % textButtonBackgroundPaths.count], withExtension: nil)!)
        }
        #if os(macOS)
        let image = imageData.map({ NSImage(data: $0)! })
        #else
        let image = imageData.map({ UIImage(data: $0)! })
        #endif
        let font = label.attributedText?.attribute(.font, at: 0, effectiveRange: nil) as? Font ?? Font(name: label.fontName!, size: label.fontSize)!
        var frame = CGRect(x: 0, y: font.descender, width: label.frame.width, height: font.ascender - font.descender)
        let marginMultiplier = ClientConfiguration.shared.theme.textButtonPadding ?? CGSize(width: 0.35, height: 0.25)
        let margin = CGSize(width: frame.height * marginMultiplier.width, height: frame.height * marginMultiplier.height)
        frame = frame.insetBy(dx: -margin.width, dy: -margin.height)
        if let image = image {
            frame.size.width = max(frame.width, frame.height / image.size.height * image.size.width)
        }
        frame.size.width = max(minWidth, frame.size.width)
        switch horizontalAlignment {
        case .center:
            frame.origin.x -= frame.width / 2
        case .left:
            break
        case .right:
            frame.origin.x -= frame.width
        @unknown default:
            break
        }
        frame.origin.x += margin.width
        if let image = image {
            background.path = CGPath(rect: frame, transform: nil)
            background.fillColor = .white
            background.lineWidth = 0
            let originalFrame = (left: CGRect(x: 0, y: 0, width: image.size.width / 2, height: image.size.height), right: CGRect(x: image.size.width / 2, y: 0, width: image.size.width / 2, height: image.size.height))
            let resizedFrame = (left: CGRect(x: 0, y: 0, width: image.size.width / 2 / image.size.height * frame.height, height: frame.height), right: CGRect(x: frame.width - (image.size.width / 2 / image.size.height * frame.height), y: 0, width: image.size.width / 2 / image.size.height * frame.height, height: frame.height))
            #if os(macOS)
            let resizedImage = NSImage(size: frame.size, flipped: false) { _ in
                image.draw(in: resizedFrame.left, from: originalFrame.left, operation: .copy, fraction: 1)
                image.draw(in: CGRect(x: resizedFrame.left.maxX - 0.5, y: 0, width: frame.width + 1 - resizedFrame.left.width - resizedFrame.right.width, height: resizedFrame.left.height), from: CGRect(x: originalFrame.left.maxX, y: 0, width: 1, height: originalFrame.left.height), operation: .copy, fraction: 1)
                image.draw(in: resizedFrame.right, from: originalFrame.right, operation: .copy, fraction: 1)
                return true
            }
            #else
            let resizedImage = UIGraphicsImageRenderer(size: frame.size).image { context in
                image.draw(in: resizedFrame.left, from: originalFrame.left, blendMode: .copy, alpha: 1)
                image.draw(in: CGRect(x: resizedFrame.left.maxX - 0.5, y: 0, width: frame.width + 1 - resizedFrame.left.width - resizedFrame.right.width, height: resizedFrame.left.height), from: CGRect(x: originalFrame.left.maxX, y: 0, width: 1, height: originalFrame.left.height), blendMode: .copy, alpha: 1)
                image.draw(in: resizedFrame.right, from: originalFrame.right, blendMode: .copy, alpha: 1)
            }
            #endif
            background.fillTexture = SKTexture(image: resizedImage)
        } else {
            background.path = CGPath(roundedRect: frame, cornerWidth: font.pointSize * 0.6, cornerHeight: font.pointSize * 0.6, transform: nil)
            background.fillColor = Color(white: 0.3, alpha: 0.9)
            background.strokeColor = .white.withAlphaComponent(0.5)
        }
        label.position.x = frame.midX
        shadow.position = label.position + CGPoint(x: 1, y: -1)
    }
    
    private var _tap: ((Scene2D.HitTestResult) -> Void)?
    public override var tap: ((Scene2D.HitTestResult) -> Void)? {
        get {
            _tap
        }
        set {
            _tap = if let newValue = newValue, let sound = ClientConfiguration.shared.theme.textButtonTapSoundPath {
                { result in
                    newValue(result)
                    PreparedResources.sound(named: sound).currentTime = 0
                    PreparedResources.sound(named: sound).play()
                }
            } else {
                newValue
            }
        }
    }
    
}

#if os(iOS)
extension UIImage {
    
    func draw(in rect: CGRect, from: CGRect, blendMode: CGBlendMode, alpha: CGFloat) {
        UIImage(cgImage: cgImage!.cropping(to: from)!).draw(in: rect, blendMode: blendMode, alpha: alpha)
    }
    
}
#endif
