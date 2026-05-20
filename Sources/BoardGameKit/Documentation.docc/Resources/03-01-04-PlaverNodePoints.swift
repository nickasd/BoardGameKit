import BoardGameKit
import SceneKit

final class CrazyEightsPlayerNode: SCNNode, GamePlayerNode3D {
    
    let id: UUID
    var overlay: PlayerOverlay?
    
    private(set) var handCards: CardNodeFan!
    private(set) var points: TextTicker2D!
    
    init(localizedPlayer: LocalizedPlayer) {
        self.id = localizedPlayer.id
        super.init()
        
        handCards = CardNodeFan(maximumWidth: 0.1, maximumChildSpacing: 0.03)
        handCards.simdPosition = Vector3(x: 0, y: 0.05, z: 0)
        handCards.simdOrientation = Rotation(x: -0.6)
        addChildNode(handCards)
        
        points = TextTicker2D(string: 0.formatted())
        
        overlay = PlayerOverlay(localizedPlayer: localizedPlayer, customView: points)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
