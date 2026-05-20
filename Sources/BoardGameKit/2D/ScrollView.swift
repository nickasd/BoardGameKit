import SpriteKit

public class ScrollView: SKCropNode {
    
    public let content: SKNode
    public var contentSize = CGSize.zero {
        didSet {
            contentOffset.y += -(contentSize.height - oldValue.height)
        }
    }
    
    private let background: SKShapeNode
    private var dragStartContentNodePosition: CGPoint?
    private var decelerationTimer: Timer?

    public override init() {
        content = SKNode()
        let maskNode = SKShapeNode()
        maskNode.lineWidth = 0
        maskNode.fillColor = .white
        background = SKShapeNode(rect: .zero)
        background.lineWidth = 0
        background.zPosition = -10
        super.init()
        self.maskNode = maskNode // SKCropNode.maskNode in SCNView.overlaySKScene causes app crash when resizing window (FB14799641)
        addChild(content)
        addChild(background)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public var size = CGSize.zero {
        didSet {
            let path = CGPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5), cornerWidth: 10, cornerHeight: 10, transform: nil)
            (maskNode as! SKShapeNode).path = path
            background.path = path
        }
    }
    
    private var contentOffset: CGPoint {
        get {
            return content.position
        }
        set {
            content.position = CGPoint(x: constrainContentOffsetComponent(newValue.x, toMax: -(contentSize.width - size.width)), y: constrainContentOffsetComponent(newValue.y, toMax: -(contentSize.height - size.height)))
        }
    }
    
    private func constrainContentOffsetComponent(_ component: Double, toMax max: Double) -> Double {
        return component < max || max > 0 ? max : component > 0 ? 0 : component
    }
    
    func panStart() {
        if let decelerationTimer = decelerationTimer {
            decelerationTimer.invalidate()
            self.decelerationTimer = nil
        }
        dragStartContentNodePosition = content.position
    }
    
    func panUpdate(withTranslation translation: CGPoint) {
        let dragStartContentNodePosition = self.dragStartContentNodePosition!
        contentOffset = dragStartContentNodePosition + translation
    }
    
    func panEnd(withTranslation translation: CGPoint, velocity: CGPoint) {
        let speed = (velocity.x * velocity.x + velocity.y * velocity.y).squareRoot()
        if speed > 0 {
            let date = Date()
            decelerationTimer = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [self] timer in
                let newSpeed = max(0, speed + 0.1 * date.timeIntervalSinceNow)
                if newSpeed > 0 {
                    let speedRatio = newSpeed / speed
                    let translation = translation + speedRatio * velocity
                    MainActor.assumeIsolated {
                        panUpdate(withTranslation: translation)
                    }
                } else {
                    timer.invalidate()
                    MainActor.assumeIsolated {
                        decelerationTimer = nil
                        dragStartContentNodePosition = nil
                    }
                }
            }
        } else {
            dragStartContentNodePosition = nil
        }
    }
    
}
