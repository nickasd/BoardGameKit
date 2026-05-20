import BoardGameKitHost

final class CrazyEightsGame: Game {
    
    static var requiredPlayerCount = 2...7
    
    private let players: [CrazyEightsPlayer]
    private var actionHandler: GameActionHandler<CrazyEightsState, CrazyEightsPlayer, CrazyEightsPlayerState>! = .init(.start)
    
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
    
}

struct CrazyEightsOptions: GameOptions {
}

enum CrazyEightsState: String, GameState {
    case start
}
