import BoardGameKitHost

final class CrazyEightsGame: Game {
    
    static var requiredPlayerCount = 2...7
    
    private let players: [CrazyEightsPlayer]
    private var actionHandler: GameActionHandler<CrazyEightsState, CrazyEightsPlayer, CrazyEightsPlayerState>! = .init(.start)
    
    private let playerCardCount = 5
    private var cardDeck = RecordedArray(Card.allCards)
    private var playedCards = RecordedArray<Card>()
    
    init(savedPlayers: [SavedPlayer], options: CrazyEightsOptions) throws {
        players = savedPlayers.map({ CrazyEightsPlayer(id: $0.id) })
        
        actionHandler.register(startGame, state: .start)
        actionHandler.register(playCard, state: .play)
    }
    
    func initialAction() -> any GameAction {
        return StartGameAction()
    }
    
    func handle(context: GameActionContext) throws {
        try actionHandler.handle(context: context)
    }
    
    func close() {
        actionHandler = nil
    }
    
    struct StartGameAction: ReplayableGameAction {
        static let name = "startGame"
        
        struct ReplayData: Codable {
            let cards: [UUID: [String]]
        }
    }
    
    struct StartGameEvent: GameEvent {
        static let name = "startGame"
        
        let cards: [UUID: [String]]
    }
    
    private func startGame(data: StartGameAction, replay: inout StartGameAction.ReplayData?, context: GameActionContext) throws {
        for player in players {
            let cards = try cardDeck.draw(count: playerCardCount, ids: replay?.cards.get(for: player.id))
            player.handCards.append(contentsOf: cards)
        }
        replay = .init(cards: Dictionary(uniqueKeysWithValues: players.map({ ($0.id, $0.handCards.ids) })))
        context.sendToAllPlayers(StartRoundEvent(cards: Dictionary(uniqueKeysWithValues: players.map({ ($0.id, $0.handCards.ids) }))))
        actionHandler.setGameWaiting()
        actionHandler.setState(.play, for: players[0])
    }
    
    struct PlayCardAction: GameAction {
        static let name = "playCard"
        
        let card: String
    }
    
    struct PlayCardEvent: GameEvent {
        static let name = "playCard"
        
        let player: UUID
        let card: String
    }
    
    private func playCard(player: CrazyEightsPlayer, data: PlayCardAction, context: GameActionContext) throws {
        let (card, index) = try player.handCards.get(id: data.card)
        if !validatePlayCard(card) {
            throw HostError.validationFailed
        }
        playedCards.append(player.handCards.remove(at: index))
        context.sendToAllPlayers(PlayCardEvent(player: player.id, card: card.id))
        actionHandler.setWaiting(player)
        actionHandler.setState(.play, for: players.wrappedElement(after: player))
    }
    
    func validatePlayCard(_ card: Card) -> Bool {
        guard let last = playedCards.last else {
            return true
        }
        return card.suit == last.suit || card.rank == last.rank || card.rank == 8
    }
    
}

struct CrazyEightsOptions: GameOptions {
}

enum CrazyEightsState: String, GameState {
    case start
}
