import BoardGameKit
import SceneKit

final class CrazyEightsPlayerNode: SCNNode, GamePlayerNode3D {
    
    let id: UUID
    
    init(localizedPlayer: LocalizedPlayer) {
        self.id = localizedPlayer.id
        super.init()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
