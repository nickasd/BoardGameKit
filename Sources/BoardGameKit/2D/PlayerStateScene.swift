import BoardGameKitHost
import SpriteKit

class PlayerStateScene: Scene2D {
    
    @MainActor class Player: Identifiable {
        let id: UUID
        let iconNode: PlayerIcon?
        let nameNode: TextNode2D
        let activeTimeNode: TextNode2D
        let actionCountNode: TextNode2D
        var state: GameManager.EventGroup.PlayerState?
        var activeTimer: Timer?
        
        init(localizedPlayer: LocalizedPlayer) {
            id = localizedPlayer.id
            iconNode = PlayerIcon(size: 40, name: localizedPlayer.gameCharacter?.icon, borderWidth: 1, borderColor: .gray)
            nameNode = TextNode2D(string: localizedPlayer.name, fontSize: 25, horizontalAlignment: .left, verticalAlignment: .center)
            activeTimeNode = TextNode2D(string: "", fontSize: 25, horizontalAlignment: .right, verticalAlignment: .center)
            actionCountNode = TextNode2D(string: "", fontSize: 25, horizontalAlignment: .right, verticalAlignment: .center)
        }
    }
    
    private var previousScene: Scene2D!
    private let players: [Player]
    private var background: SKShapeNode!
    private var closeButton: ImageButton2D!
    private var content: SKNode!
    private var startDate = Date()
    
    init(localizedPlayers: [LocalizedPlayer]) {
        self.players = localizedPlayers.map({ Player(localizedPlayer: $0) })
        super.init()
        
        background = SKShapeNode()
        background.fillColor = Color(white: 0.2, alpha: 0.95)
        background.lineWidth = 0
        addChild(background)
        
        closeButton = ImageButton2D(systemName: "xmark.circle")
        closeButton.tap = { [unowned self] _ in
            deactivate()
            transition(to: previousScene)
            previousScene = nil
        }
        addChild(closeButton)
        
        let labelContainer = SKNode()
        
        let activeTimeContainer = SKNode()
        let activeTimeLabel = TextNode2D(string: NSLocalizedString("playerState.activeTime", bundle: .boardGameKit, value: "Time", comment: ""), fontSize: 25, horizontalAlignment: .right)
        activeTimeLabel.position = CGPoint(x: 0, y: -25)
        activeTimeContainer.addChild(activeTimeLabel)
        
        let actionCountContainer = SKNode()
        let actionCountLabel = TextNode2D(string: NSLocalizedString("playerState.moves", bundle: .boardGameKit, value: "Moves", comment: ""), fontSize: 25, horizontalAlignment: .right)
        actionCountLabel.position = CGPoint(x: 0, y: -25)
        actionCountContainer.addChild(actionCountLabel)
        
        for (i, player) in self.players.enumerated() {
            let y = -25 - Double(i + 1) * 50
            if let iconNode = player.iconNode {
                iconNode.position = CGPoint(x: 20, y: y)
                labelContainer.addChild(iconNode)
                player.nameNode.position = CGPoint(x: 50, y: y)
            } else {
                player.nameNode.position = CGPoint(x: 0, y: y)
            }
            labelContainer.addChild(player.nameNode)
            player.activeTimeNode.position = CGPoint(x: 0, y: y)
            activeTimeContainer.addChild(player.activeTimeNode)
            player.actionCountNode.position = CGPoint(x: 0, y: y)
            actionCountContainer.addChild(player.actionCountNode)
        }
        
        content = SKNode()
        labelContainer.position = CGPoint(x: 0, y: 0)
        content.addChild(labelContainer)
        activeTimeContainer.position = CGPoint(x: labelContainer.calculateAccumulatedFrame().maxX + 200, y: 0)
        content.addChild(activeTimeContainer)
        actionCountContainer.position = CGPoint(x: activeTimeContainer.position.x + 150, y: 0)
        content.addChild(actionCountContainer)
        addChild(content)
    }
    
    required override init() {
        fatalError("init() has not been implemented")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func willAppear() {
        previousScene = Scene2D.current
    }
    
    override func layout() {
        super.layout()
        background.path = CGPath(rect: unsafeSceneFrame, transform: nil)
        closeButton.position = CGPoint(x: sceneFrame.maxX - 50, y: sceneFrame.maxY - 50)
        let contentFrame = content.calculateAccumulatedFrame()
        content.position = CGPoint(x: -contentFrame.width / 2, y: contentFrame.height / 2)
    }
    
    func activate() {
        for player in players {
            if player.state?.activeTimeStart != nil {
                startActiveTimer(for: player)
            } else {
                player.activeTimeNode.string = activeTimeString(for: player.state?.activeTime ?? 0)
            }
            player.actionCountNode.string = actionCountString(for: player.state?.actionCount ?? 0)
        }
    }
    
    func deactivate() {
        for player in players {
            stopActiveTimer(for: player)
        }
    }
    
    func setPlayerStates(_ states: [GameManager.EventGroup.PlayerState]) {
        for state in states {
            let player = players.first(id: state.id)!
            setState(state, for: player)
            if parent != nil {
                if state.activeTimeStart == nil {
                    stopActiveTimer(for: player)
                } else if player.activeTimer == nil {
                    startActiveTimer(for: player)
                }
            }
        }
        if states.allSatisfy({ $0.state == nil }) {
            deactivate()
        }
    }
    
    private func setState(_ state: GameManager.EventGroup.PlayerState?, for player: Player) {
        let oldState = player.state
        player.state = state
        if parent != nil {
            player.activeTimeNode.string = activeTimeString(for: state?.activeTime ?? 0)
            player.actionCountNode.string = actionCountString(for: state?.actionCount ?? 0)
        }
        
        GameContext.current.undoManager?.addEvent(UndoManager.Event(id: "PlayerStatisticsView.setState") { [self] in
            setState(oldState, for: player)
        })
    }
    
    private func startActiveTimer(for player: Player) {
        let start = max(player.state!.activeTimeStart!, startDate)
        let time = player.state!.activeTime - start.timeIntervalSinceNow
        player.activeTimeNode.string = activeTimeString(for: floor(time))
        player.activeTimer = Timer(fire: Date(timeIntervalSinceNow: 1 - time.truncatingRemainder(dividingBy: 1)), interval: 1, repeats: true) { [self] _ in
            MainActor.assumeIsolated {
                player.activeTimeNode.string = activeTimeString(for: player.state.map({ $0.activeTime - start.timeIntervalSinceNow }) ?? 0)
            }
        }
        RunLoop.current.add(player.activeTimer!, forMode: .common)
    }
    
    private func stopActiveTimer(for player: Player) {
        if let activeTimer = player.activeTimer {
            activeTimer.invalidate()
            player.activeTimer = nil
        }
    }
    
    private func activeTimeString(for time: TimeInterval) -> String {
        if #available(macOS 13.0, iOS 16.0, *) {
            return Duration.seconds(time).formatted(.time(pattern: time < 60 * 60 ? .minuteSecond(padMinuteToLength: 2, fractionalSecondsLength: 1) : .hourMinuteSecond(padHourToLength: 2, fractionalSecondsLength: 1)))
        } else {
            let formatter = NumberFormatter()
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 2
            return formatter.string(from: time as NSNumber)!
        }
    }
    
    private func actionCountString(for count: Int) -> String {
        return count.formatted()
    }
    
}
