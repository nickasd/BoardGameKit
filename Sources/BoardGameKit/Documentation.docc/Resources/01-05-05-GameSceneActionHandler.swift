import BoardGameKit
import SceneKit

final class CrazyEightsGameScene: SCNNode, GameScene3D {
    
    var players = [CrazyEightsPlayerNode]()
    var localPlayer: CrazyEightsPlayerNode?
    var focusedPlayer: CrazyEightsPlayerNode?
    var actionHandler: (any GameSceneActionHandler3D)?
    
}
