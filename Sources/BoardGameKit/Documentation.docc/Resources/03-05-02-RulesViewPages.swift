import BoardGameKit
import SpriteKit

class CrazyEightsRulesView: SKNode {
    
    override init() {
        super.init()
        addChild(page1())
        addChild(page2())
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func page1() -> SKNode {
        return TextNode2D(string: NSLocalizedString("rules.1", value: "Play a card with the same rank or suit as the one on the table.\n\nWhen you play an 8, you decide what rank or suit the next player has to play.\n\nIf you cannot or don't want to play a card, you draw one.", comment: ""), maxWidth: 800)
    }
    
    private func page2() -> SKNode {
        return TextNode2D(string: NSLocalizedString("rules.1", value: "The first player who empties their hand, wins!", comment: ""), maxWidth: 800)
    }
    
}
