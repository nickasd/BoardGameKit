import BoardGameKitHost
import SpriteKit
#if os(iOS)
import UIKit
#endif

extension SKNode {
    
    /// Temporarily highlights the node red to signal an invalid action.
    public func runInvalidUseAnimation() {
        run(.sequence([
            .universalColorize(with: .red, colorBlendFactor: 0.8, duration: 0.5),
            .universalColorize(with: .white, colorBlendFactor: 1, duration: 0.5)
        ]))
        for node in children {
            node.runInvalidUseAnimation()
        }
    }
    
    /// Marks the node as highlighted (or not) with an animation.
    public func highlight(_ highlight: Bool) {
        if highlight {
            run(.universalColorize(with: .yellow, colorBlendFactor: 0.8, duration: 0.3))
        } else {
            run(.universalColorize(with: .white, colorBlendFactor: 1, duration: 0.3))
        }
        for child in children {
            child.highlight(highlight)
        }
    }
    
    /// Shows or hides the node with an animation.
    public func showChild(_ node: SKNode, _ show: Bool) {
        if show {
            addChildAndFadeIn(node)
        } else {
            node.fadeOutAndRemoveFromParent()
        }
    }
    
    public func addChildAndFadeIn(_ node: SKNode) {
        node.alpha = 0
        node.run(.sequence([
            .wait(forDuration: 0.01), // SKNode.zPosition causes nodes to flicker by switching position for 1 frame (FB15945016)
            .fadeAlpha(to: (node as? ButtonNode2D)?.isEnabled == false ? ButtonNode2D.disabledAlpha : 1, duration: 0.2)
        ]), withKey: "show")
        if node.parent == nil {
            addChild(node)
        }
    }
    
    public func fadeOutAndRemoveFromParent() {
        run(.sequence([
            .fadeOut(withDuration: 0.2),
            .run { [weak self] in
                Task { @MainActor in
                    self?.removeFromParent() // SKAction.removeFromParent() causes crash when run in SCNView.overlaySKScene (FB15498049)
                }
            }
        ]), withKey: "show")
    }
    
}

extension SKAction {
    
    static func universalColorize(with color: Color, colorBlendFactor: CGFloat, duration: TimeInterval) -> SKAction {
        var start: Color?
        return .customAction(withDuration: duration) { node, t in
            switch node {
            case let node as SKSpriteNode:
                if start == nil {
                    start = node.color
                }
                node.color = start!.blended(withFraction: colorBlendFactor, of: color)
            case let node as SKShapeNode:
                if start == nil {
                    start = node.fillColor
                }
                node.fillColor = start!.blended(withFraction: colorBlendFactor, of: color)
            default:
                break
            }
        }
    }
    
    public func withTimingMode(_ timingMode: SKActionTimingMode) -> SKAction {
        self.timingMode = timingMode
        return self
    }
    
}

extension Color {
    
    var components: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        #if os(macOS)
        switch colorSpace.colorSpaceModel {
        case .gray:
            var white = CGFloat(0)
            var alpha = CGFloat(0)
            getWhite(&white, alpha: &alpha)
            return (white, white, white, alpha)
        case .rgb:
            var red = CGFloat(0)
            var green = CGFloat(0)
            var blue = CGFloat(0)
            var alpha = CGFloat(0)
            getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            return (red, green, blue, alpha)
        default:
            preconditionFailure()
        }
        #else
        var red = CGFloat(0)
        var green = CGFloat(0)
        var blue = CGFloat(0)
        var alpha = CGFloat(0)
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (red, green, blue, alpha)
        #endif
    }
    
    func blended(withFraction colorBlendFactor: Double, of color: Color) -> Color {
        let (red1, green1, blue1, alpha1) = components
        let (red2, green2, blue2, alpha2) = color.components
        return Color(red: simd_mix(red1, red2, colorBlendFactor), green: simd_mix(green1, green2, colorBlendFactor), blue: simd_mix(blue1, blue2, colorBlendFactor), alpha: simd_mix(alpha1, alpha2, colorBlendFactor))
    }
    
}

extension SKShapeNode {
    
    public convenience init(texture: SKTexture, rectOf size: CGSize, cornerRadius: CGFloat = 0) {
        self.init(rectOf: size, cornerRadius: cornerRadius)
        fillTexture = texture
        fillColor = .white
        lineWidth = 0
    }
    
}

extension CGPoint {
    
    public static func + (left: CGPoint, right: CGPoint) -> CGPoint {
        return CGPoint(x: left.x + right.x, y: left.y + right.y)
    }
    
    public static func - (left: CGPoint, right: CGPoint) -> CGPoint {
        return CGPoint(x: left.x - right.x, y: left.y - right.y)
    }
    
    public static func * (left: Double, right: CGPoint) -> CGPoint {
        return CGPoint(x: left * right.x, y: left * right.y)
    }

}

class ChainFilter: CIFilter {
    
    let filters: [CIFilter]
    @objc dynamic var inputImage: CIImage?
    
    init(filters: [CIFilter]) {
        self.filters = filters
        super.init()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var outputImage: CIImage? {
        get {
            var image = inputImage
            for filter in filters {
                filter.setValue(image, forKey: "inputImage")
                image = filter.outputImage
            }
            return image
        }
    }
}

extension SKEffectNode {
    
    public convenience init(shadow: SKNode, radius: Float = 10) {
        self.init()
        shouldRasterize = true
        shouldEnableEffects = true
        addChild(shadow)
        let filter1 = CIFilter.morphologyMaximum()
        filter1.radius = radius
        let filter2 = CIFilter.boxBlur()
        filter2.radius = radius
        filter = ChainFilter(filters: [filter1, filter2])
    }
    
}

class PlayerIcon: SKNode {
    
    private let border: SKShapeNode
    private let borderWidth: Double
    
    init(size: Double, name: String?, borderWidth: Double, borderColor: Color, shadowColor: Color? = nil) {
        border = SKShapeNode(ellipseOf: CGSize(width: size, height: size))
        if let playerIconsPath = ClientConfiguration.shared.playerIconsPath, let name = name {
            border.fillTexture = PreparedResources.texture(named: "\(playerIconsPath)/\(name)")
            border.fillColor = .white
        }
        border.lineWidth = borderWidth
        border.strokeColor = borderColor
        self.borderWidth = borderWidth
        super.init()
        
        if let shadowColor = shadowColor {
            let shadow = SKShapeNode(ellipseOf: CGSize(width: size + borderWidth, height: size + borderWidth))
            shadow.fillColor = shadowColor
            shadow.lineWidth = 0
            addChild(SKEffectNode(shadow: shadow))
        }
        addChild(border)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setBorderColorAnimated(_ color: Color) {
        border.run(.sequence([
            .customAction(withDuration: 0.3, actionBlock: { [self] _, t in // Using SCNAction.customAction(duration:action:) causes crash with Swift 6 language mode (FB15570385)
                border.lineWidth = borderWidth * (1.0 - t / 0.3)
            }),
            .run { [self] in // Using SCNAction.customAction(duration:action:) causes crash with Swift 6 language mode (FB15570385)
                border.strokeColor = color
            },
            .customAction(withDuration: 0.3, actionBlock: { [self] _, t in // Using SCNAction.customAction(duration:action:) causes crash with Swift 6 language mode (FB15570385)
                border.lineWidth = borderWidth * (t / 0.3)
            })
        ]))
    }
    
}
