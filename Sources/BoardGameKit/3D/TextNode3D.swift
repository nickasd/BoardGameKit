import BoardGameKitHost
import SceneKit

public class TextNode3D: ButtonNode3D {
    
    private let text: SCNText
    
    public init(string: Any?, fontName: String? = nil, fontSize: Double, extrusionDepth: Double = 0, alignment: CATextLayerAlignmentMode = .natural, color: Color = .white) {
        text = SCNText(string: string, extrusionDepth: extrusionDepth)
        text.alignmentMode = alignment.rawValue
        self.string = string
        super.init()
        #if os(macOS)
        text.font = NSFont(name: fontName ?? text.font.fontName, size: fontSize)
        #else
        text.font = UIFont(name: fontName ?? text.font.fontName, size: fontSize)
        #endif
        text.firstMaterial!.isDoubleSided = true
        text.firstMaterial!.diffuse.contents = color
        text.flatness = 0.1
        addChildNode(SCNNode(geometry: text))
        childNodes[0].simdScale = Vector3(repeating: 0.001)
        updateAlignment()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @Recorded public var string: Any? {
        didSet {
            text.string = string
            updateAlignment()
        }
    }
    
    private func updateAlignment() {
        switch CATextLayerAlignmentMode(rawValue: text.alignmentMode) {
        case .left:
            pivot = SCNMatrix4MakeTranslation(0, 0, 0)
        case .center:
            pivot = SCNMatrix4MakeTranslation((boundingBox.max.x + boundingBox.min.x) / 2, 0, 0)
        case .right:
            pivot = SCNMatrix4MakeTranslation(boundingBox.max.x, 0, 0)
        default:
            break
        }
    }
    
}
