import BoardGameKitHost
import SpriteKit

/// A text ticker can update its text with a scroll animation.
public class TextTicker2D: SKNode {
    
    @Recorded private var text: TextNode2D
    
    public init(string: String) {
        text = TextNode2D(string: string, fontSize: 20, horizontalAlignment: .left, shadowColor: .black.withAlphaComponent(0.9))
        super.init()
        addChild(text)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func setText(_ text: String, timeOffset: TimeInterval = 0, duration: TimeInterval) {
        let oldText = self.text
        if oldText.string == text {
            return
        }
        let text = TextNode2D(string: text, fontSize: 20, horizontalAlignment: .left, shadowColor: .black.withAlphaComponent(0.9))
        self.text = text
        let timeline = GameSceneContext.current.timeline
        timeline.addAnimation(TimelineAnimation(id: "TextTicker2D.setText", subject: self, startTime: timeline.currentTime + timeline.timeOffset + timeOffset, duration: duration, enter: { [self] direction in
            switch direction {
            case .forward:
                text.removeFromParent()
                addChild(text)
            case .backward:
                oldText.removeFromParent()
                addChild(oldText)
            }
        }, progress: { t in
            let t = MoveAnimation.TimingMode.easeInEaseOut.apply(t: t)
            oldText.alpha = 1 - t
            oldText.position = CGPoint(x: 0, y: 20 * t)
            text.alpha = t
            text.position = CGPoint(x: 0, y: 20 * (t - 1))
        }, exit: { direction in
            switch direction {
            case .forward:
                oldText.removeFromParent()
            case .backward:
                text.removeFromParent()
            }
        }))
    }
    
}
