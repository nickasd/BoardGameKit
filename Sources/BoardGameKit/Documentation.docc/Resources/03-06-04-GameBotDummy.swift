import BoardGameKitHost

extension CrazyEightsGame: GameBot {
    
    func action(for player: UUID, strategy: CrazyEightsStrategy) throws -> (any GameAction)? {
        return switch strategy {
        case .dummy:
            try randomAction(for: player)
        }
    }
    
    private func randomAction(for player: UUID) throws -> (any GameAction)? {
        var actions = [any GameAction]()
        let (player, state) = try actionHandler.state(for: player)
        for state in state {
            switch state {
            case .play:
                actions.append(contentsOf: player.handCards.filter({ validatePlayCard($0) }).map({ CrazyEightsGame.PlayCardAction(card: $0.id) }))
                if actions.isEmpty {
                    actions.append(DrawCardAction())
                }
            case .chooseRankSuit:
                actions.append(contentsOf: (Card.rankRange.map({ RankSuit.rank($0) }) + Card.Suit.allCases.map({ RankSuit.suit($0) })).map({ CrazyEightsGame.ChooseRankSuitAction(rankSuit: $0) }))
            }
        }
        return actions.randomElement()
    }
    
}

enum CrazyEightsStrategy: String, GameStrategy {
    case dummy
}
