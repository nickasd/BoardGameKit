import BoardGameKit
import BoardGameKitHost
import SceneKit

final class CrazyEightsGameScene: SCNNode, GameScene3D {
    
    var players = [CrazyEightsPlayerNode]()
    var localPlayer: CrazyEightsPlayerNode?
    var focusedPlayer: CrazyEightsPlayerNode?
    var actionHandler: (any GameSceneActionHandler3D)?
    private let table = CrazyEightsTableNode()
    private var eventHandler: GameSceneEventHandler<CrazyEightsPlayerNode, CrazyEightsPlayerState>! = .init()
    private let gameSceneContext = GameSceneContext.current
    
    func load(localizedPlayers: [LocalizedPlayer], options: CrazyEightsOptions) async throws {
        players = localizedPlayers.map({ CrazyEightsPlayerNode(localizedPlayer: $0) })
        positionPlayers(players, mainPosition: .init(x: 0, y: 0.2), otherPositions: .arc(minRadius: 0.2, distanceBetweenPoints: 0.2), hostPlayer: gameSceneContext.hostPlayer)
        for player in players {
            addChildNode(player)
        }
        addChildNode(table)
        
        eventHandler.register(startGame)
        eventHandler.register(playCard)
    }
    
    func handle(eventGroup: GameManager.EventGroupResponse) throws {
        try eventHandler.handle(eventGroup: eventGroup)
    }
    
    func handle(error: GameManager.GameErrorResponse) throws {
        try eventHandler.handle(error: error)
    }
    
    func close() {
        eventHandler = nil
    }
    
    func hidePrivateData(_ hide: Bool, for player: CrazyEightsPlayerNode) {
    }
    
    func enableActions(_ enable: Bool, for player: CrazyEightsPlayerNode) {
    }
    
    // MARK: - Play
    
    private func startGame(data: CrazyEightsGame.StartGameEvent) {
        for (playerId, cards) in data.cards {
            let player = players.first(id: playerId)!
            player.handCards.appendNewNodes(table.cardDeck.lastChildNodes(withNames: cards))
            player.handCards.animateNodes()
        }
    }
    
    private func playCard(data: CrazyEightsGame.PlayCardEvent) {
        let player = players.first(id: data.player)!
        table.playedCards.appendNewNode(player.handCards.firstChildNode(withName: data.card))
        table.playedCards.animateNodes()
    }
    
}
