import SpriteKit

class TimelineView: SKNode {
    
    private(set) var barContainer: ButtonNode2D!
    private var knob: SKShapeNode!
    private var backwardSpeedLabel: TextNode2D!
    private(set) var backwardButton: ButtonNode2D!
    private(set) var playButton: ImageButton2D!
    private(set) var forwardButton: ButtonNode2D!
    private var forwardSpeedLabel: TextNode2D!
    private var markers: SKNode!
    private var liveMarker: SKShapeNode!
    private var currentTimeLabel: TextNode2D!
    private var durationLabel: TextNode2D!
    let barFrame = CGRect(x: -200, y: -2, width: 400, height: 4)

    override init() {
        super.init()
        let background = SKShapeNode(rect: CGRect(x: -360, y: -30, width: 720, height: 120), cornerRadius: 20)
        background.fillColor = Color(white: 0.2, alpha: 0.95)
        background.strokeColor = .white.withAlphaComponent(0.5)
        addChild(background)
        
        let bar = SKShapeNode(rect: barFrame)
        bar.lineWidth = 0
        bar.fillColor = .gray
        addChild(bar)
        
        markers = SKNode()
        markers.position = CGPoint(x: barFrame.minX, y: barFrame.midY)
        addChild(markers)
        
        liveMarker = SKShapeNode(rectOf: CGSize(width: 4, height: 10))
        liveMarker.lineWidth = 0
        liveMarker.fillColor = .systemGreen
        addChild(liveMarker)
        
        knob = SKShapeNode(rectOf: CGSize(width: 10, height: 20), cornerRadius: 5)
        knob.lineWidth = 0
        knob.fillColor = .white
        addChild(knob)
        
        let barInteraction = SKShapeNode(rect: barFrame.insetBy(dx: 0, dy: -8))
        barInteraction.lineWidth = 0
        barInteraction.fillColor = .clear
        barContainer = ButtonNode2D()
        barContainer.addChild(barInteraction)
        addChild(barContainer)
        
        backwardSpeedLabel = TextNode2D(string: "", fontSize: 15, horizontalAlignment: .right, verticalAlignment: .center)
        backwardSpeedLabel.position = CGPoint(x: -120, y: 45)
        addChild(backwardSpeedLabel)
        
        backwardButton = ImageButton2D(systemName: ClientConfiguration.shared.theme.imageButtonBackgroundPath != nil ? "backward.circle" : "backward.fill", width: 50)
        backwardButton.position = CGPoint(x: -80, y: 45)
        addChild(backwardButton)
        
        playButton = ImageButton2D(systemName: ClientConfiguration.shared.theme.imageButtonBackgroundPath != nil ? "play.circle" : "play.fill", width: 50)
        playButton.position = CGPoint(x: 0, y: 45)
        addChild(playButton)
        
        forwardButton = ImageButton2D(systemName: ClientConfiguration.shared.theme.imageButtonBackgroundPath != nil ? "forward.circle" : "forward.fill", width: 50)
        forwardButton.position = CGPoint(x: 80, y: 45)
        addChild(forwardButton)
        
        forwardSpeedLabel = TextNode2D(string: "", fontSize: 15, horizontalAlignment: .left, verticalAlignment: .center)
        forwardSpeedLabel.position = CGPoint(x: 120, y: 45)
        addChild(forwardSpeedLabel)
        
        currentTimeLabel = TextNode2D(string: "", fontSize: 20, horizontalAlignment: .right, verticalAlignment: .center)
        currentTimeLabel.position = CGPoint(x: barFrame.minX - 20, y: barFrame.midY)
        currentTimeLabel.numberOfLines = 0 // this prevents the following bug: SKLabelNode keeps jumping back and forth when displaying different numbers with equal number of digits (FB15553700)
        addChild(currentTimeLabel)

        durationLabel = TextNode2D(string: "", fontSize: 20, horizontalAlignment: .left, verticalAlignment: .center)
        durationLabel.position = CGPoint(x: barFrame.maxX + 20, y: barFrame.midY)
        addChild(durationLabel)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    var rate = 0.0 {
        didSet {
            if rate < 0 || oldValue < 0 {
                backwardSpeedLabel.string = rate < 0 ? String(format: "%@x", (-rate).formatted()) : ""
            }
            if (rate == 0) != (oldValue == 0) {
                playButton.setSystemImage(rate == 0 ? (ClientConfiguration.shared.theme.imageButtonBackgroundPath != nil ? "play.circle" : "play.fill") : (ClientConfiguration.shared.theme.imageButtonBackgroundPath != nil ? "pause.circle" : "pause.fill"))
            }
            if (rate > 0 && rate != 1) || (oldValue > 0 && oldValue != 1) {
                forwardSpeedLabel.string = rate > 0 && rate != 1 ? String(format: "%@x", rate.formatted()) : ""
            }
        }
    }
    
    var duration = TimeInterval(0) {
        didSet {
            currentTimeLabel.string = timeString(for: currentTime)
            durationLabel.string = timeString(for: duration)
        }
    }
    
    var currentTime = TimeInterval(0) {
        didSet {
            currentTimeLabel.string = timeString(for: currentTime) // SKLabelNode keeps jumping back and forth when displaying different numbers with equal number of digits (FB15553700), SceneKit app randomly crashes with EXC_BAD_ACCESS in jet_context::set_fragment_texture (FB15081598)
            knob.position = CGPoint(x: barFrame.minX + currentTime / duration * barFrame.width, y: barFrame.midY)
        }
    }
    
    private func timeString(for timeInterval: TimeInterval) -> String {
        if #available(macOS 13.0, iOS 16.0, *) {
            return Duration.seconds(timeInterval).formatted(.time(pattern: duration < 60 * 60 ? .minuteSecond(padMinuteToLength: 2, fractionalSecondsLength: 2) : .hourMinuteSecond(padHourToLength: 2, fractionalSecondsLength: 2)))
        } else {
            let formatter = NumberFormatter()
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 2
            return formatter.string(from: timeInterval as NSNumber)!
        }
    }
    
    func setMarkers(_ markers: [TimeInterval], liveTime: TimeInterval) {
        let diff = markers.count - self.markers.children.count
        if diff < 0 {
            self.markers.removeChildren(in: Array(self.markers.children[0..<(-diff)]))
        } else if diff > 0 {
            for _ in 0..<diff {
                let node = SKShapeNode(rectOf: CGSize(width: 2, height: barFrame.height))
                node.lineWidth = 0
                node.fillColor = .white
                self.markers.addChild(node)
            }
        }
        for (marker, node) in zip(markers, self.markers.children) {
            node.position = CGPoint(x: marker / duration * barFrame.width, y: 0)
        }
        liveMarker!.position = CGPoint(x: barFrame.minX + liveTime / duration * barFrame.width, y: barFrame.midY)
    }
    
}
