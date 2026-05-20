import SpriteKit

open class ButtonNode2D: SKNode {
    
    static let disabledAlpha = 0.5
    
    public var tap: ((Scene2D.HitTestResult) -> Void)?
    public var drag: (start: ((ButtonNode2D) -> ButtonNode2D), update: ((ButtonNode2D, CGPoint) -> Void)?, end: ((ButtonNode2D) -> Void)?)?
    public var isEnabled = true
    
    public func enable(_ enable: Bool) {
        isEnabled = enable
        alpha = enable ? 1 : ButtonNode2D.disabledAlpha
    }
    
}
