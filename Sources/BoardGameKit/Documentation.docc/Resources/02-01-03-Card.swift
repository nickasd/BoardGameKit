final class Card: Identifiable {
    
    enum Suit: String, CaseIterable {
        case diamond
        case heart
        case club
        case spade
    }
    
    static let rankRange = 1...13
    static let allCards = Suit.allCases.flatMap({ suit in rankRange.map({ rank in Card(id: "\(suit) \(rank)", suit: suit, rank: rank) }) })
    
    let id: String
    let suit: Suit
    let rank: Int
    
    init(id: String, suit: Suit, rank: Int) {
        self.id = id
        self.suit = suit
        self.rank = rank
    }
    
}
