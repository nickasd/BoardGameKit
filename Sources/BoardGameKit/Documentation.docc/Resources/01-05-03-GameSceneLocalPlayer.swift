import BoardGameKit
import SceneKit

final class CrazyEightsGameScene: SCNNode, GameScene3D {
    
    var players = [CrazyEightsPlayerNode]()
    var localPlayer: CrazyEightsPlayerNode?
    
}
