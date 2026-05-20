import SceneKit

@MainActor open class ButtonNode3D: SCNNode {
    
    public struct DropPoint {
        let parent: SCNNode
        let transform: Transform
        let action: (ButtonNode3D) -> Void
        
        public init(parent: SCNNode, transform: Transform, action: @escaping (ButtonNode3D) -> Void) {
            self.parent = parent
            self.transform = transform
            self.action = action
        }
    }
    
    public var tap: ((Scene3D.HitTestResult) -> Void)?
    public var longPress: (start: (Scene3D.HitTestResult) -> Void, end: ((ButtonNode3D) -> Void)?)?
    public var drag: (start: ((Scene3D.HitTestResult) -> ButtonNode3D), end: ((ButtonNode3D) -> Void)?)?
    public var dropPoints = [DropPoint]() {
        didSet {
            firstAncestor({ $0 as? GameSceneManager3D })?.didUpdateDropPoints(of: self, oldDropPoints: oldValue)
        }
    }
    public var isEnabled = true
    public internal(set) var activeDropPoint: Int?
    
}
