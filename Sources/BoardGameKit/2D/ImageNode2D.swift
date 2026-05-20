import SpriteKit

public class ImageNode2D: SKNode {
    
    private let sprite: SKSpriteNode
    private let width: Double
    private let color: Color
    
    public init(systemName: String, width: Double = 60, color: Color = .white, shadowColor: Color? = nil) {
        sprite = SKSpriteNode()
        self.width = width
        self.color = color
        super.init()
        if let shadowColor = shadowColor {
            addChild(SKEffectNode(shadow: ImageNode2D(systemName: systemName, width: width, color: shadowColor)))
        }
        setSystemImage(systemName)
        addChild(sprite)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func setSystemImage(_ systemName: String) {
        #if os(macOS)
        var image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)!.withSymbolConfiguration(.init(hierarchicalColor: color))!
        let scale = GameViewController.shared.view.window!.screen!.backingScaleFactor
        image.size = CGSize(width: width * scale, height: width / image.size.width * image.size.height * scale)
        #else
        var image = UIImage(systemName: systemName)!.applyingSymbolConfiguration(.init(pointSize: width))!.applyingSymbolConfiguration(.init(hierarchicalColor: color))! // SKTexture initialized with UIImage has slightly wrong aspect ratio and ignores system symbol color (FB15095279)
        image = UIImage(data: image.pngData()!, scale: GameViewController.shared.view.traitCollection.displayScale)!
        #endif
        sprite.texture = SKTexture(image: image)
        sprite.size = CGSize(width: width, height: width / image.size.width * image.size.height)
    }
    
}

public class ImageButton2D: ButtonNode2D {
    
    private let sprite: SKSpriteNode
    private let width: Double
    private let color: Color
    private var background: SKSpriteNode?
    
    public init(systemName: String, width: Double = 60, color: Color = .white) {
        sprite = SKSpriteNode()
        self.width = width
        self.color = color
        super.init()
        if ClientConfiguration.shared.theme.imageButtonBackgroundPath != nil {
            background = SKSpriteNode()
            background!.size = CGSize(width: width, height: width)
            addChild(background!)
        }
        setSystemImage(systemName)
        addChild(sprite)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func setSystemImage(_ systemName: String, color: Color? = nil) {
        var systemName = systemName
        if let background = background, let imageButtonBackgroundPath = ClientConfiguration.shared.theme.imageButtonBackgroundPath {
            if let imageButtonAlternateBackgroundPath = ClientConfiguration.shared.theme.imageButtonAlternateBackgroundPath, let range = systemName.range(of: ".fill", options: .backwards), systemName[..<range.lowerBound].hasSuffix(".circle") {
                systemName = String(systemName[..<range.lowerBound])
                background.texture = PreparedResources.texture(named: imageButtonAlternateBackgroundPath)
            } else {
                background.texture = PreparedResources.texture(named: imageButtonBackgroundPath)
            }
        }
        let color = color ?? self.color
        #if os(macOS)
        var image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)!.withSymbolConfiguration(.init(hierarchicalColor: color))!
        let scale = GameViewController.shared.view.window!.screen!.backingScaleFactor
        image.size = CGSize(width: width * scale, height: width / image.size.width * image.size.height * scale)
        #else
        var image = UIImage(systemName: systemName)!.applyingSymbolConfiguration(.init(pointSize: width))!.applyingSymbolConfiguration(.init(hierarchicalColor: color))! // SKTexture initialized with UIImage has slightly wrong aspect ratio and ignores system symbol color (FB15095279)
        image = UIImage(data: image.pngData()!, scale: GameViewController.shared.view.traitCollection.displayScale)!
        #endif
        var width = width
        if background != nil {
            if systemName.hasSuffix(".circle") {
                width *= 1.1
                let cropRadius = image.size.width * 0.2
                #if os(macOS)
                let originalImage = image
                image = NSImage(size: image.size, flipped: false) { _ in
                    NSGraphicsContext.saveGraphicsState()
                    NSBezierPath(roundedRect: CGRect(origin: .zero, size: originalImage.size).insetBy(dx: cropRadius, dy: cropRadius), xRadius: .infinity, yRadius: .infinity).setClip()
                    originalImage.draw(in: CGRect(origin: .zero, size: originalImage.size))
                    NSGraphicsContext.restoreGraphicsState()
                    return true
                }
                #else
                image = UIGraphicsImageRenderer(size: image.size).image { context in
                    context.cgContext.saveGState()
                    UIBezierPath(roundedRect: CGRect(origin: .zero, size: image.size).insetBy(dx: cropRadius, dy: cropRadius), cornerRadius: .infinity).addClip()
                    image.draw(at: .zero)
                    context.cgContext.restoreGState()
                }
                #endif
            } else {
                width *= 0.6
            }
        }
        sprite.texture = SKTexture(image: image)
        sprite.size = CGSize(width: width, height: width / image.size.width * image.size.height)
    }
    
    private var _tap: ((Scene2D.HitTestResult) -> Void)?
    public override var tap: ((Scene2D.HitTestResult) -> Void)? {
        get {
            _tap
        }
        set {
            _tap = if let newValue = newValue, let sound = ClientConfiguration.shared.theme.imageButtonTapSoundPath {
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

public class BackButton: ButtonNode2D {
    
    public override init() {
        super.init()
        if let backButtonBackgroundPath = ClientConfiguration.shared.theme.backButtonBackgroundPath {
            let width = 50.0
            let texture = PreparedResources.texture(named: backButtonBackgroundPath)
            addChild(SKSpriteNode(texture: texture, size: CGSize(width: width, height: width / texture.size().width * texture.size().height)))
        } else {
            addChild(ImageNode2D(systemName: "chevron.backward.circle"))
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
