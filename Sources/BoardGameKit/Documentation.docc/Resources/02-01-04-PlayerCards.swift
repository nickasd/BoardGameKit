import BoardGameKitHost

final class CrazyEightsPlayer: GamePlayer {
    
    let id: UUID
    
    var handCards = RecordedArray<Card>()
    
    init(id: UUID) {
        self.id = id
    }
    
}

enum CrazyEightsPlayerState: String, GameState {
    case play
}
