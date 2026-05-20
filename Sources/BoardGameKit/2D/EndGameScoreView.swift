import BoardGameKitHost
import SpriteKit

class EndGameScoreView: SKNode {
    
    init(localizedPlayers: [LocalizedPlayer], ranking: [(player: UUID, text: String)], buttons: [ImageButton2D]) {
        super.init()
        let labelsContainer = SKNode()
        let pointsContainer = SKNode()
        for (i, (id, text)) in ranking.enumerated() {
            let player = localizedPlayers.first(id: id)!
            let y = -45 - Double(i) * 60
            
            let icon = PlayerIcon(size: 50, name: player.gameCharacter?.icon, borderWidth: 1, borderColor: .gray)
            icon.position = CGPoint(x: 30, y: y + 15)
            labelsContainer.addChild(icon)
            let label = TextNode2D(string: player.name, horizontalAlignment: .left)
            label.position = CGPoint(x: 80, y: y)
            labelsContainer.addChild(label)
            
            let points = TextNode2D(string: text, horizontalAlignment: .right)
            points.position = CGPoint(x: 0, y: y)
            pointsContainer.addChild(points)
        }
        
        let ranking = SKNode()
        ranking.addChild(labelsContainer)
        pointsContainer.position.x = labelsContainer.calculateAccumulatedFrame().size.width + pointsContainer.calculateAccumulatedFrame().size.width + 50
        ranking.addChild(pointsContainer)
        let rankingSize = ranking.calculateAccumulatedFrame()
        
        let content = SKNode()
        let title = TextNode2D(string: NSLocalizedString("game.endscore.title", bundle: .boardGameKit, value: "End Game Score", comment: ""))
        let contentWidth = max(ranking.calculateAccumulatedFrame().width, title.calculateAccumulatedFrame().width)
        title.position = CGPoint(x: contentWidth / 2, y: -30)
        content.addChild(title)
        
        ranking.position = CGPoint(x: (contentWidth - rankingSize.width) / 2, y: -70)
        content.addChild(ranking)
        
        for (i, button) in buttons.enumerated() {
            button.position = CGPoint(x: contentWidth / 2 - (Double(buttons.count - 1) / 2 - Double(i)) * 100, y: -rankingSize.height - 140)
            content.addChild(button)
        }
        
        let contentSize = content.calculateAccumulatedFrame()
        content.position = CGPoint(x: -contentSize.width / 2, y: contentSize.height / 2)
        let background = SKShapeNode(rectOf: contentSize.insetBy(dx: -40, dy: -40).size, cornerRadius: 40)
        background.fillColor = Color(white: 0.2, alpha: 0.95)
        background.strokeColor = .white.withAlphaComponent(0.5)
        addChild(background)
        addChild(content)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
