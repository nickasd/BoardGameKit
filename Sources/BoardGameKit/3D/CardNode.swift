import SceneKit
import SpriteKit

public enum CardFormat {
    case standardPortrait
    case standardLandscape
    case smallPortrait
    case smallLandscape
    case bigPortrait
    case bigLandscape
    case custom(Vector2, Double)
    
    public var size: Vector2 {
        return switch self {
        case .standardPortrait:
            Vector2(x: 0.056, y: 0.087)
        case .standardLandscape:
            Vector2(x: 0.087, y: 0.056)
        case .smallPortrait:
            Vector2(x: 0.043, y: 0.067)
        case .smallLandscape:
            Vector2(x: 0.067, y: 0.043)
        case .bigPortrait:
            Vector2(x: 0.079, y: 0.12)
        case .bigLandscape:
            Vector2(x: 0.12, y: 0.079)
        case .custom(let size, _):
            size
        }
    }
    
    public var cornerRadius: Double {
        return switch self {
        case .custom(_, let cornerRadius):
            cornerRadius
        default:
            0.005
        }
    }
    
    public func geometry() -> SCNGeometry {
        let plane = SCNPlane(width: Double(size.x), height: Double(size.y))
        plane.cornerRadius = cornerRadius
        return plane
    }
    
    func placeholderImage() -> CGImage {
        let width = 500
        let context = CGContext(data: nil, width: width, height: Int(Float(width) / size.x * size.y), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let lineWidth = 30.0
        context.setLineWidth(lineWidth)
        context.setLineDash(phase: 0, lengths: [80, 80])
        context.setStrokeColor(Color(red: 0.16, green: 0.16, blue: 0.18, alpha: 0.8).cgColor)
        context.move(to: CGPoint(x: lineWidth / 2, y: lineWidth / 2))
        context.addLine(to: CGPoint(x: Double(context.width) - lineWidth / 2, y: lineWidth / 2))
        context.addLine(to: CGPoint(x: Double(context.width) - lineWidth / 2, y: Double(context.height) - lineWidth / 2))
        context.addLine(to: CGPoint(x: lineWidth / 2, y: Double(context.height) - lineWidth / 2))
        context.addLine(to: CGPoint(x: lineWidth / 2, y: lineWidth / 2))
        context.strokePath()
        return context.makeImage()!
    }
    
    /// Create a material that displays the given text.
    public func materialDescribing(_ string: String) -> SCNMaterial {
        let width = 500.0
        let height = width / Double(size.x) * Double(size.y)
        let cornerRadius = width * cornerRadius / Double(size.x)
        let scene = SKScene(size: CGSize(width: width, height: height))
        
        let border = SKShapeNode(rect: CGRect(x: 0, y: 0, width: width, height: height), cornerRadius: cornerRadius)
        border.strokeColor = .white
        border.lineWidth = 10
        scene.addChild(border)
        
        let label = SKLabelNode(text: String(repeating: "\(string) ", count: 100))
        label.fontSize = 40
        label.horizontalAlignmentMode = .left
        label.verticalAlignmentMode = .top
        label.numberOfLines = 0
        label.preferredMaxLayoutWidth = width - cornerRadius * 2
        label.position = CGPoint(x: cornerRadius, y: cornerRadius)
        label.yScale = -1
        scene.addChild(label)
        
        return SCNMaterial(diffuseContents: scene)
    }
}

public class CardNode: GameElementNode, HideableNode {
    
    public static let thickness = Float(0.00025)
    public static let dragOffsetY = Vector3(x: 0, y: 0.01, z: 0)

    private let frontMaterial: (String) -> SCNMaterial
    private let backMaterial: SCNMaterial
    
    /// Initialize a card by making two copies of the given `geometry`, one for the front and one for the back, with the given materials. Common card geometries can be created with `CardFormat.geometry()`.
    public init(geometry: SCNGeometry, frontMaterial: @escaping (String) -> SCNMaterial, backMaterial: SCNMaterial) {
        self.frontMaterial = frontMaterial
        self.backMaterial = backMaterial
        super.init()
        let frontNode = SCNNode(geometry: geometry.copy(withMaterials: [backMaterial]))
        addChildNode(frontNode)
        let backNode = SCNNode(geometry: geometry.copy(withMaterials: [backMaterial]))
        backNode.eulerAngles.y = .pi
        addChildNode(backNode)
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func show(_ name: String) {
        childNodes[0].geometry!.materials[0] = frontMaterial(name)
    }
    
    public func hide() {
        childNodes[0].geometry!.materials[0] = backMaterial
    }
    
}

public class StaticCardNode: CardNode {
    
    /// Initialize a card by making two copies of the given `geometry`, one for the front and one for the back, with the given materials. Common card geometries can be created with `CardFormat.geometry()`.
    public init(name: String, geometry: SCNGeometry, frontMaterial: SCNMaterial, backMaterial: SCNMaterial) {
        super.init(geometry: geometry, frontMaterial: { _ in frontMaterial }, backMaterial: backMaterial)
        self.name = name
        show(name)
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}

public class FixedCardNodeGroup: FixedNodeGroup<CardNode> {
}

public class CardNodeArray: NodeArray<CardNode> {
}

public class CardNodeStack: NodeStack<CardNode> {
}

public class CardNodeDeck: NodeDeck<CardNode> {
    
    public let cardFormat: CardFormat
    
    private let frontMaterial: (String) -> SCNMaterial
    private let backMaterial: () -> SCNMaterial
    lazy var cardGeometry = cardFormat.geometry()
    
    public init(cardFormat: CardFormat, front frontMaterial: @escaping (String) -> SCNMaterial, back backMaterial: @escaping () -> SCNMaterial) {
        self.cardFormat = cardFormat
        self.frontMaterial = frontMaterial
        self.backMaterial = backMaterial
        super.init(distance: Vector3(x: 0, y: CardNode.thickness, z: 0))
        childRotation = Rotation(x: -.pi / 2, z: .pi)
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func initialize(count: Int) {
        let backMaterial = backMaterial()
        initialize((0..<count).map({ _ in CardNode(geometry: cardGeometry, frontMaterial: frontMaterial, backMaterial: backMaterial) }))
    }
    
    public func dropPointPlaceholder() -> SCNNode {
        let placeholder = SCNNode(geometry: cardGeometry)
        placeholder.geometry!.firstMaterial!.diffuse.contents = cardFormat.placeholderImage()
        return placeholder
    }
    
}

public class CardNodeDiscardPile: CardNodeArray {
    
    public init() {
        super.init(distance: Vector3(x: 0, y: CardNode.thickness, z: 0))
        defer {
            hideChildren = false
        }
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override var hideChildren: Bool {
        didSet {
            childRotation = Rotation(x: -.pi / 2, z: hideChildren ? .pi : 0)
        }
    }
    
}

public class CardNodeFan: NodeGroup<CardNode> {
    
    public var childRotation = Rotation(y: -0.03)

    private let maximumChildSpacing: Float
    private let maximumWidth: Float
    private let center: Bool
    
    /// Child nodes are spaced at `maximumChildSpacing` from one another. If `center` is `true` (the default), the array of children is centered on the node's origin; if it is `false`, the first child is placed at the origin of the node.
    public init(maximumWidth: Float, maximumChildSpacing: Float, center: Bool = true) {
        self.maximumWidth = maximumWidth
        self.maximumChildSpacing = maximumChildSpacing
        self.center = center
        super.init()
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func transform(ofChildAt index: Int) -> Transform {
        let distance = min(maximumChildSpacing, maximumWidth / Float(childNodes.count - 1))
        let start = center ? -Float(childNodes.count - 1) / 2 * distance : .zero
        return Transform(position: Vector3(x: start + Float(index) * distance, y: 0, z: 0), rotation: childRotation)
    }

}
