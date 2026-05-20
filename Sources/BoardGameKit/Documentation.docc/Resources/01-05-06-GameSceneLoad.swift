import BoardGameKit
import BoardGameKitHost
import SceneKit

final class CrazyEightsGameScene: SCNNode, GameScene3D {
    
    var players = [CrazyEightsPlayerNode]()
    var localPlayer: CrazyEightsPlayerNode?
    var focusedPlayer: CrazyEightsPlayerNode?
    var actionHandler: (any GameSceneActionHandler3D)?
    private let gameSceneContext = GameSceneContext.current
    
    func load(localizedPlayers: [LocalizedPlayer], options: CrazyEightsOptions) async throws {
        players = localizedPlayers.map({ CrazyEightsPlayerNode(localizedPlayer: $0) })
        positionPlayers(players, mainPosition: .init(x: 0, y: 0.2), otherPositions: .arc(minRadius: 0.2, distanceBetweenPoints: 0.2), hostPlayer: gameSceneContext.hostPlayer)
        for player in players {
            addChildNode(player)
        }
    }
    
}
