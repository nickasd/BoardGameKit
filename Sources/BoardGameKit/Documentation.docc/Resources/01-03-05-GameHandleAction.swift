import BoardGameKitHost

final class CrazyEightsGame: Game {
    
    static var requiredPlayerCount = 2...7
    
    private let players: [CrazyEightsPlayer]
    
    init(savedPlayers: [SavedPlayer], options: CrazyEightsOptions) throws {
        players = savedPlayers.map({ CrazyEightsPlayer(id: $0.id) })
    }
    
    func initialAction() -> any GameAction {
        return StartGameAction()
    }
    
    func handle(context: GameActionContext) throws {
    }
    
    struct StartGameAction: GameAction {
        static let name = "startGame"
    }
    
}

struct CrazyEightsOptions: GameOptions {
}
