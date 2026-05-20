import BoardGameKit
import BoardGameKitHost
import SpriteKit

class ChooseRankSuitDialog: SKNode {
    
    struct State {
        let choiceAction: (RankSuit) -> Void
    }
    
    private(set) var title: TextNode2D!
    private(set) var buttons: ButtonNode2D!
    
    override init() {
        super.init()
        title = TextNode2D(string: "")
        addChild(title)
        buttons = ButtonNode2D()
        addChild(buttons)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @Recorded var state: State? {
        didSet {
            setstate(state)
        }
    }
    
    func setstate(_ state: State?) {
        buttons.removeAllChildren()
        guard let state = state else {
            return
        }
        title.string = NSLocalizedString("chooseRankSuitDialog.title", value: "Choose rank or suit:", comment: "")
        title.position = CGPoint(x: 0, y: 150)
        
        for (rank, point) in zip(Card.rankRange, PointGenerator.line(maxLength: 1000, maxDistanceBetweenPoints: .init(x: 80, y: 0)).generate(count: Card.rankRange.count)) {
            let button = TextButton2D(string: rank.formatted())
            button.name = String(decoding: try! JSONEncoder().encode(RankSuit.rank(rank)), as: UTF8.self)
            button.position = CGPoint(x: Double(point.position.x), y: 40 + Double(point.position.y))
            buttons.addChild(button)
        }
        for (suit, point) in zip(Card.Suit.allCases, PointGenerator.line(maxLength: 1000, maxDistanceBetweenPoints: .init(x: 150, y: 0)).generate(count: Card.Suit.allCases.count)) {
            let button = TextButton2D(string: suit.rawValue)
            button.name = String(decoding: try! JSONEncoder().encode(RankSuit.suit(suit)), as: UTF8.self)
            button.position = CGPoint(x: Double(point.position.x), y: -40 + Double(point.position.y))
            buttons.addChild(button)
        }
        buttons.tap = { result in
            guard let item = result.descendants.first else {
                return
            }
            state.choiceAction(try! JSONDecoder().decode(RankSuit.self, from: Data(item.name!.utf8)))
        }
    }
    
}
