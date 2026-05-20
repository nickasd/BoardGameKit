import BoardGameKit
import SceneKit

class CrazyEightsTableNode: SCNNode {
    
    private(set) var cardDeck: CardNodeDeck!
    private(set) var playedCards: CardNodeDiscardPile!
    
    override init() {
        super.init()
        
        cardDeck = CardNodeDeck(cardFormat: .standardPortrait, front: { CardFormat.standardPortrait.materialDescribing($0) }, back: { .black })
        cardDeck.simdPosition = Vector3(x: -0.1, y: 0.001, z: 0)
        cardDeck.initialize(count: Card.allCards.count)
        addChildNode(cardDeck)
        
        playedCards = CardNodeDiscardPile()
        playedCards.simdPosition = Vector3(x: 0, y: 0.001, z: 0)
        addChildNode(playedCards)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
