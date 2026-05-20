import BoardGameKitHost

extension CrazyEightsGame: GameBot {
    
    func action(for player: UUID, strategy: CrazyEightsStrategy) throws -> (any GameAction)? {
        
    }
    
}

enum CrazyEightsStrategy: String, GameStrategy {
    case dummy
}
