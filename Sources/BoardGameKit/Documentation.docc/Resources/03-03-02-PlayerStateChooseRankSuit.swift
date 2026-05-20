import BoardGameKitHost

final class CrazyEightsPlayer: GamePlayer {
    
    let id: UUID
    
    var handCards = RecordedArray<Card>()
    @Recorded var points = 0
    
    init(id: UUID) {
        self.id = id
    }
    
}

enum CrazyEightsPlayerState: String, GameState {
    case play
    case chooseRankSuit
}
