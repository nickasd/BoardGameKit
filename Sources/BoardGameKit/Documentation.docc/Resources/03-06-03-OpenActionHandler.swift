import BoardGameKitHost

final class CrazyEightsGame: Game {
    
    static var requiredPlayerCount = 2...7
    
    private let players: [CrazyEightsPlayer]
    private(set) var actionHandler: GameActionHandler<CrazyEightsState, CrazyEightsPlayer, CrazyEightsPlayerState>! = .init(.start)
    
    private let playerCardCount = 5
    private var cardDeck = RecordedArray(Card.allCards)
    private var playedCards = RecordedArray<Card>()
    @Recorded private var chosenRankSuit: RankSuit?
    
    init(savedPlayers: [SavedPlayer], options: CrazyEightsOptions) throws {
        players = savedPlayers.map({ CrazyEightsPlayer(id: $0.id) })
        
        actionHandler.register(startRound, state: .start)
        actionHandler.register(playCard, state: .play)
        actionHandler.register(chooseRankSuit, state: .chooseRankSuit)
        actionHandler.register(drawCard, state: .play)
    }
    
    func initialAction() -> any GameAction {
        return StartRoundAction()
    }
    
    func handle(context: GameActionContext) throws {
        try actionHandler.handle(context: context)
    }
    
    func close() {
        actionHandler = nil
    }
    
    struct StartRoundAction: ReplayableGameAction {
        static let name = "startRound"
        
        struct ReplayData: Codable {
            let cards: [UUID: [String]]
        }
    }
    
    struct StartRoundEvent: PrivateGameEvent {
        static let name = "startRound"
        
        struct PrivateData: Codable {
            let cards: [String]
        }
        
        let cardCount: Int
    }
    
    private func startRound(data: StartRoundAction, replay: inout StartRoundAction.ReplayData?, context: GameActionContext) throws {
        for player in players {
            let cards = try cardDeck.draw(count: playerCardCount, ids: replay?.cards.get(for: player.id))
            player.handCards.append(contentsOf: cards)
        }
        replay = .init(cards: Dictionary(uniqueKeysWithValues: players.map({ ($0.id, $0.handCards.ids) })))
        context.sendToAllPlayers(StartRoundEvent(cardCount: playerCardCount), privateData: .init({ .init(cards: $0.handCards.ids) }, for: players))
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
        let chooseRankSuit: Bool?
    }
    
    private func playCard(player: CrazyEightsPlayer, data: PlayCardAction, context: GameActionContext) throws {
        let (card, index) = try player.handCards.get(id: data.card)
        if !validatePlayCard(card) {
            throw PlayCardEvent.Failure(card: card.id)
        }
        playedCards.append(player.handCards.remove(at: index))
        chosenRankSuit = nil
        context.sendToAllPlayers(PlayCardEvent(player: player.id, card: card.id, chooseRankSuit: !player.handCards.isEmpty && card.rank == 8))
        actionHandler.setWaiting(player)
        if player.handCards.isEmpty {
            endRound(player: player, context: context)
        } else if card.rank == 8 {
            actionHandler.setState(.chooseRankSuit, for: player)
        } else {
            actionHandler.setState(.play, for: players.wrappedElement(after: player))
        }
    }
    
    func validatePlayCard(_ card: Card) -> Bool {
        guard let last = playedCards.last else {
            return true
        }
        return switch chosenRankSuit {
        case nil:
            card.suit == last.suit || card.rank == last.rank || card.rank == 8
        case .rank(let rank):
            card.rank == rank
        case .suit(let suit):
            card.suit == suit
        }
    }
    
    struct ChooseRankSuitAction: GameAction {
        static let name = "chooseRankSuit"
        
        let rankSuit: RankSuit
    }
    
    struct ChooseRankSuitEvent: GameEvent {
        static let name = "chooseRankSuit"
        
        let rankSuit: RankSuit
    }
    
    private func chooseRankSuit(player: CrazyEightsPlayer, data: ChooseRankSuitAction, context: GameActionContext) throws {
        chosenRankSuit = data.rankSuit
        context.sendToAllPlayers(ChooseRankSuitEvent(rankSuit: data.rankSuit))
        actionHandler.setWaiting(player)
        actionHandler.setState(.play, for: players.wrappedElement(after: player))
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
        if players.allSatisfy({ $0.points < players.count * 50 }) {
            cardDeck.append(contentsOf: players.flatMap({ $0.handCards.removeAndReturnAll() }) + playedCards.removeAndReturnAll())
            actionHandler.setGameState(.start)
            context.queue(action: StartRoundAction())
        } else {
            endGame(context: context)
        }
    }
    
    struct EndGameEvent: GameEvent {
        static let name = "endGame"
        
        let points: [UUID: Int]
    }
    
    private func endGame(context: GameActionContext) {
        context.sendToAllPlayers(EndGameEvent(points: Dictionary(uniqueKeysWithValues: players.map({ ($0.id, $0.points) }))))
    }
    
}

struct CrazyEightsOptions: GameOptions {
}

enum CrazyEightsState: String, GameState {
    case start
}
