import BoardGameKitHost
import SceneKit

@MainActor public class PointTokenTracker: SCNNode {
    
    /// The duration of the token movement from one point to the next. The default is `0.5`.
    public var speed = TimeInterval(0.5)
    /// The duration of the whole token movement performed by the last call to `moveToken(for:by:)`.
    public private(set) var lastMovementDuration = TimeInterval(0)
    
    private let tokens: [UUID: GameElementNode]
    private var tokenGroups: RecordedDictionary<Int, NodeGroup<GameElementNode>>!
    private unowned let delegate: PointTokenTrackerDelegate

    public init(delegate: PointTokenTrackerDelegate, tokens: [(player: UUID, node: GameElementNode)]) {
        self.delegate = delegate
        self.tokens = Dictionary(uniqueKeysWithValues: tokens)
        super.init()
        let group = tokenGroup(for: 0)
        tokenGroups = RecordedDictionary([0: group])
        addChildNode(group)
        for (player, token) in tokens {
            token.name = player.uuidString
            token.myTransform = group.transform(ofChildAt: group.childNodes.count)
            group.addChildNode(token)
        }
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /**
     Moves the token of the given `player` by `points`.
     
     The delegate's methods are called when appropriate to determine the transform of the token for each intermediate step. A node group is created for the token's final position; when other tokens move to that position, they are added to the same group.
     
     After this method returns, the duration of the whole token movement is given by `lastMovementDuration`.
     */
    public func moveToken(for player: UUID, by points: Int, timeOffset: TimeInterval = 0) {
        if points == 0 {
            lastMovementDuration = 0
            return
        }
        let token = tokens[player]!
        let oldStack = token.parent as! NodeGroup
        let oldPoints = Int(oldStack.name!)!
        if case let endPoints = delegate.pointTokenTracker(self, effectivePointsFor: oldPoints + points), tokenGroups[endPoints] == nil {
            let stack = tokenGroup(for: endPoints)
            tokenGroups[endPoints] = stack
            addNode(stack)
        }
        for i in 1...abs(points) {
            let oldStack = token.parent as? NodeParent
            let points = delegate.pointTokenTracker(self, effectivePointsFor: oldPoints + points.signum() * i)
            if let stack = tokenGroups[points] {
                stack.appendNewNode(token)
                stack.animateNodes(timeOffset: timeOffset + TimeInterval(i) * speed)
            } else {
                convertAndAddChildNode(token)
                addAnimation(MoveAnimation(node: token, timingMode: .easeOut, endTransform: delegate.pointTokenTracker(self, transformFor: points), duration: speed, timeOffset: timeOffset + TimeInterval(i) * speed))
            }
            oldStack?.animateNodes(timeOffset: timeOffset + TimeInterval(i) * speed)
        }
        if oldStack.childNodes.isEmpty {
            removeNode(oldStack)
            let _ = tokenGroups.removeValue(forKey: oldPoints)
        }
        lastMovementDuration = TimeInterval(abs(points)) * speed
    }
    
    private func tokenGroup(for points: Int) -> NodeGroup<GameElementNode> {
        let stack = delegate.pointTokenTracker(self, nodeGroupFor: points)
        stack.name = "\(points)"
        stack.animationPath = .linear
        stack.animationDuration = speed
        stack.myTransform = delegate.pointTokenTracker(self, transformFor: points)
        return stack
    }
    
}

@MainActor public protocol PointTokenTrackerDelegate: AnyObject {
    /**
     Returns the effective points for the given `points`.
     
     Often point trackers on game boards have a loop. For example, a game might show steps for all numbers between 0 and 99, and if a token goes beyond the last step, 99, it starts again at 0. In this case, the implementation of this method is simply `points % 100`. This number will then be passed to the other delegate methods, `pointTokenTracker(_:nodeGroupFor:)` and `pointTokenTracker(_:transformFor:)`.
     */
    func pointTokenTracker(_ pointTokenTracker: PointTokenTracker, effectivePointsFor points: Int) -> Int
    /// Returns a node group for the given step index.
    func pointTokenTracker(_ pointTokenTracker: PointTokenTracker, nodeGroupFor points: Int) -> NodeGroup<GameElementNode>
    /// Returns the transform of a token or node group for the given step index.
    func pointTokenTracker(_ pointTokenTracker: PointTokenTracker, transformFor points: Int) -> Transform
}
