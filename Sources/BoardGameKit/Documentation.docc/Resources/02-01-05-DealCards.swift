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
    
    struct StartGameAction: GameAction {
        static let name = "startGame"
    }
    
    private func startGame(data: StartGameAction, context: GameActionContext) throws {
        for player in players {
            let cards = try cardDeck.draw(count: playerCardCount, ids: nil)
            player.handCards.append(contentsOf: cards)
        }
        actionHandler.setGameWaiting()
    }
    
}

struct CrazyEightsOptions: GameOptions {
}

enum CrazyEightsState: String, GameState {
    case start
}
