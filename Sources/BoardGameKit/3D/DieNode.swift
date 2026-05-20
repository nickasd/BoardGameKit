import SceneKit

public class DieNode: GameElementNode {
    
    public let size: Float
    
    public static func frontSideRotation(for die: Int) -> Rotation {
        return switch die {
        case 1:
            Rotation(x: 0, y: 0, z: 0)
        case 2:
            Rotation(x: 0, y: -.pi / 2, z: 0)
        case 3:
            Rotation(x: 0, y: .pi, z: 0)
        case 4:
            Rotation(x: 0, y: .pi / 2, z: 0)
        case 5:
            Rotation(x: .pi / 2, y: 0, z: 0)
        case 6:
            Rotation(x: -.pi / 2, y: 0, z: 0)
        default:
            fatalError()
        }
    }
    
    public static func upSideRotation(for die: Int) -> Rotation {
        return Rotation(x: -.pi / 2) * frontSideRotation(for: die)
    }
    
    public init(size: Float = 0.016, faceMaterials: [SCNMaterial]) {
        self.size = size
        super.init()
        geometry = Box(width: size, height: size, length: size, chamferRadius: size / 3)
        geometry!.materials = faceMaterials
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
