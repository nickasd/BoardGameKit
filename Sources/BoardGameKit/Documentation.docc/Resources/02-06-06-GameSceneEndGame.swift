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
        
        eventHandler.register(startRound)
        eventHandler.register(playCard)
        eventHandler.register(drawCard)
        eventHandler.register(endRound)
        eventHandler.register(endGame)
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
        player.handCards.hideChildren = hide
    }
    
    func enableActions(_ enable: Bool, for player: CrazyEightsPlayerNode) {
        for state in eventHandler.state(for: player) {
            switch state {
            case .play:
                player.handCards.isEnabled = enable
                player.handCards.tap = selectCard
                table.cardDeck.isEnabled = enable
                table.cardDeck.tap = selectCardDeck
            }
        }
    }
    
    // MARK: - Play
    
    private func startRound(data: CrazyEightsGame.StartRoundEvent, privateData: CrazyEightsGame.StartRoundEvent.PrivateDataList?) {
        for (i, player) in players.enumerated() {
            if let privateData = privateData?.get(for: player.id) {
                player.handCards.appendNewNodes(table.cardDeck.lastChildNodes(withNames: privateData.cards))
            } else {
                player.handCards.appendNewNodes(table.cardDeck.lastChildNodes(hiddenCount: data.cardCount))
            }
            player.handCards.animateNodes(timeOffset: TimeInterval(i) / TimeInterval(players.count))
        }
    }
    
    private func selectCard(_ sender: Scene3D.HitTestResult) {
        actionHandler?.sendAction(CrazyEightsGame.PlayCardAction(card: sender.descendants[0].name!))
    }
    
    private func playCard(data: FailableGameEventResult<CrazyEightsGame.PlayCardEvent>) {
        switch data {
        case .success(let data):
            let player = players.first(id: data.player)!
            table.playedCards.appendNewNode(player.handCards.firstChildNode(withName: data.card))
            table.playedCards.animateNodes()
            addTimeOffset(1)
        case .failure(let data):
            localPlayer!.handCards.firstChildNode(withName: data.card).runInvalidUseAnimation()
        }
    }
    
    private func selectCardDeck(_ sender: Scene3D.HitTestResult) {
        actionHandler?.sendAction(CrazyEightsGame.DrawCardAction())
    }
    
    private func drawCard(data: CrazyEightsGame.DrawCardEvent, privateData: CrazyEightsGame.DrawCardEvent.PrivateDataList?) {
        let player = players.first(id: data.player)!
        if let privateData = privateData?.get(for: player.id) {
            player.handCards.appendNewNode(table.cardDeck.lastChildNode(withName: privateData.card))
        } else {
            player.handCards.appendNewNode(table.cardDeck.lastChildNodeHidden())
        }
        player.handCards.animateNodes()
        
        if data.shuffle {
            let lastCard = table.playedCards.lastChildNode!
            addAnimation(MoveAnimation(node: lastCard, path: .throughPoint(Vector3(x: 0, y: 0.1, z: 0)), endTransform: table.playedCards.transform(ofChildAt: 0), duration: 3, timeOffset: 1))
            table.cardDeck.addAbove(table.playedCards.firstChildNodes(count: table.playedCards.childNodes.count - 1))
            table.cardDeck.animateNodes(timeOffset: 2)
        }
    }
    
    private func endRound(data: CrazyEightsGame.EndRoundEvent) {
        table.cardDeck.addAbove(players.flatMap({ $0.handCards.childNodes() }) + table.playedCards.childNodes())
        table.cardDeck.animateNodes()
        addTimeOffset(1)
    }
    
    private func endGame(data: CrazyEightsGame.EndGameEvent) {
        actionHandler?.showEndGameRanking(data.points.sorted(by: { $0.value > $1.value }).map({ ($0.key, $0.value.formatted()) }))
    }
    
}
