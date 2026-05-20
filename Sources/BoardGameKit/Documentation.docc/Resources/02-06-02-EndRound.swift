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
        actionHandler.register(drawCard, state: .play)
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
    
    struct StartGameEvent: PrivateGameEvent {
        static let name = "startGame"
        
        struct PrivateData: Codable {
            let cards: [String]
        }
        
        let cardCount: Int
    }
    
    private func startGame(data: StartGameAction, replay: inout StartGameAction.ReplayData?, context: GameActionContext) throws {
        for player in players {
            let cards = try cardDeck.draw(count: playerCardCount, ids: replay?.cards.get(for: player.id))
            player.handCards.append(contentsOf: cards)
        }
        replay = .init(cards: Dictionary(uniqueKeysWithValues: players.map({ ($0.id, $0.handCards.ids) })))
        context.sendToAllPlayers(StartGameResponse(cardCount: playerCardCount), privateData: .init({ .init(cards: $0.handCards.ids) }, for: players))
        actionHandler.setGameWaiting()
        actionHandler.setState(.play, for: players[0])
    }
    
    struct PlayCardAction: GameAction {
        static let name = "playCard"
        
        let card: String
    }
    
    struct PlayCardEvent: FailableGameEvent {
        static let name = "playCard"
        
        struct Failure: GameEventFailure {
            let card: String
        }
        
        let player: UUID
        let card: String
    }
    
    private func playCard(player: CrazyEightsPlayer, data: PlayCardAction, context: GameActionContext) throws {
        let (card, index) = try player.handCards.get(id: data.card)
        if !validatePlayCard(card) {
            throw PlayCardEvent.Failure(card: card.id)
        }
        playedCards.append(player.handCards.remove(at: index))
        context.sendToAllPlayers(PlayCardEvent(player: player.id, card: card.id))
        actionHandler.setWaiting(player)
        if player.handCards.isEmpty {
            endRound(player: player, context: context)
        } else {
            actionHandler.setState(.play, for: players.wrappedElement(after: player))
        }
    }
    
    func validatePlayCard(_ card: Card) -> Bool {
        guard let last = playedCards.last else {
            return true
        }
        return card.suit == last.suit || card.rank == last.rank || card.rank == 8
    }
    
    struct DrawCardAction: ReplayableGameAction {
        static let name = "drawCard"
        
        struct ReplayData: Codable {
            let card: String
        }
    }
    
    struct DrawCardEvent: PrivateGameEvent {
        static let name = "drawCard"
        
        struct PrivateData: Codable {
            let card: String
        }
        
        let player: UUID
        let shuffle: Bool
    }
    
    private func drawCard(player: CrazyEightsPlayer, data: DrawCardAction, replay: inout DrawCardAction.ReplayData?, context: GameActionContext) throws {
        let card = try cardDeck.drawOne(id: replay?.card)
        replay = .init(card: card.id)
        player.handCards.append(card)
        let shuffle = cardDeck.isEmpty
        if shuffle {
            cardDeck.append(contentsOf: playedCards.removeAndReturnFirst(playedCards.count - 1))
        }
        context.sendToAllPlayers(DrawCardEvent(player: player.id, shuffle: shuffle), privateData: .init(.init(card: card.id), for: player))
        actionHandler.setWaiting(player)
        actionHandler.setState(.play, for: players.wrappedElement(after: player))
    }
    
    struct EndRoundEvent: GameEvent {
        static let name = "endRound"
        
        let points: [UUID: Int]
    }
    
    private func endRound(player: CrazyEightsPlayer, context: GameActionContext) {
        for player in players {
            player.points += player.handCards.map { card in
                switch card.rank {
                case 8:
                    50
                case 11, 12, 13:
                    10
                default:
                    card.rank
                }
            }.sum()
        }
        context.sendToAllPlayers(EndRoundEvent(points: Dictionary(uniqueKeysWithValues: players.map({ ($0.id, $0.points) }))))
    }
    
}

struct CrazyEightsOptions: GameOptions {
}

enum CrazyEightsState: String, GameState {
    case start
}
