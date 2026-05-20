import BoardGameKitHost

final class CrazyEightsGame: Game {
    
    static var requiredPlayerCount = 2...7
    
    private let players: [CrazyEightsPlayer]
    private var actionHandler: GameActionHandler<CrazyEightsState, CrazyEightsPlayer, CrazyEightsPlayerState>! = .init(.start)
    
    private let playerCardCount = 5
    private var cardDeck = RecordedArray(Card.allCards)
    
    init(savedPlayers: [SavedPlayer], options: CrazyEightsOptions) throws {
        players = savedPlayers.map({ CrazyEightsPlayer(id: $0.id) })
        
        actionHandler.register(startGame, state: .start)
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
    
    private func startGame(data: StartGameAction, replay: inout StartGameAction.ReplayData?, context: GameActionContext) throws {
        for player in players {
            let cards = try cardDeck.draw(count: playerCardCount, ids: replay?.cards.get(for: player.id))
            player.handCards.append(contentsOf: cards)
        }
        replay = .init(cards: Dictionary(uniqueKeysWithValues: players.map({ ($0.id, $0.handCards.ids) })))
        actionHandler.setGameWaiting()
    }
    
}

struct CrazyEightsOptions: GameOptions {
}

enum CrazyEightsState: String, GameState {
    case start
}
