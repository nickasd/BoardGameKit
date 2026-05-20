import BoardGameKitHost
import SceneKit
import SpriteKit

@MainActor public class MoveAnimation: TimelineAnimation {
    
    public enum Path {
        case linear
        case alongControlPoint(_ p1: Vector3)
        case throughPoint(_ p1: Vector3)
        case alongControlPoints(_ p1: Vector3, _ p2: Vector3)
        
        public func apply(start: Vector3, end: Vector3, t: TimeInterval) -> Vector3 {
            let t = Float(t)
            switch self {
            case .linear:
                let p0 = start
                let p1 = end
                return p0 + t * (p1 - p0)
            case .alongControlPoint(let p1):
                let p0 = start
                let p2 = end
                let _1 = (1 - t) * (1 - t) * (p0 - p1)
                let _2 = t * t * (p2 - p1)
                return p1 + _1 + _2 // "import SceneKit" causes project compile time to increase by almost 800%
            case .throughPoint(let p1):
                let p0 = start
                let p2 = end
                let _1 = 2 * p1
                let _2 = -0.5 * p0
                let _3 = -0.5 * p2
                let p1 = _1 + _2 + _3
                let _4 = (1 - t) * (1 - t) * (p0 - p1)
                let _5 = t * t * (p2 - p1)
                return p1 + _4 + _5 // "import SceneKit" causes project compile time to increase by almost 800%
            case .alongControlPoints(let p1, let p2):
                let p0 = start
                let p3 = end
                let _1 = (1 - t) * (1 - t) * (1 - t) * p0
                let _2 = 3 * (1 - t) * (1 - t) * t * p1
                let _3 = 3 * (1 - t) * t * t * p2
                let _4 = t * t * t * p3
                return _1 + _2 + _3 + _4 // "import SceneKit" causes project compile time to increase by almost 800%
            }
        }
        
        @MainActor func convert(from: SCNNode, to: SCNNode?) -> Path {
            return switch self {
            case .linear:
                self
            case .alongControlPoint(let p1):
                .alongControlPoint(from.simdConvertPosition(p1, to: to))
            case .throughPoint(let p1):
                .throughPoint(from.simdConvertPosition(p1, to: to))
            case .alongControlPoints(let p1, let p2):
                .alongControlPoints(from.simdConvertPosition(p1, to: to), from.simdConvertPosition(p2, to: to))
            }
        }
    }
    
    public enum Rotation {
        case linear
        case through(_ rotation1: BoardGameKit.Rotation)
        
        public func apply(start: BoardGameKit.Rotation, end: BoardGameKit.Rotation, t: TimeInterval) -> BoardGameKit.Rotation {
            let t = Float(t)
            switch self {
            case .linear:
                let r0 = start
                let r1 = end
                return simd_slerp(r0, r1, t)
            case .through(let rotation1):
                let r0 = start
                let r1 = rotation1
                let r2 = end
                if t < 0.55 {
                    let t = t / 0.55
                    return simd_spline(r0, r0, r1, r2, t)
                } else {
                    let t = (t - 0.55) / 0.45
                    return simd_spline(r0, r1, r2, r2, t)
                }
            }
        }
        
        @MainActor func convert(from: SCNNode, to: SCNNode?) -> Rotation {
            return switch self {
            case .linear:
                self
            case .through(let rotation1):
                .through(from.convertOrientation(rotation1, to: to))
            }
        }
    }
    
    public enum TimingMode {
        case linear
        case easeIn
        case easeOut
        case easeInEaseOut
        case quadraticEaseInEaseOut
        case cubicEaseInEaseOut
        
        public func apply(t: TimeInterval) -> TimeInterval {
            switch self {
            case .linear:
                return t
            case .easeIn:
                return 1 + cos(.pi * (1 + t / 2))
            case .easeOut:
                return sin(.pi / 2 * t)
            case .easeInEaseOut:
                return 0.5 + cos(.pi * (1 + t)) / 2
            case .quadraticEaseInEaseOut:
                var y = t
                y -= 0.5
                y = 2 * y * y
                y += 0.5
                return t < 0.5 ? 1 - y : y
            case .cubicEaseInEaseOut:
                var y = t
                y -= 0.5
                y = 4 * y * y * y
                y += 0.5
                return y
            }
        }
    }
    
    public init(node: GameElementNode, worldTransform: @escaping (_ t: TimeInterval) -> Transform, duration: TimeInterval, timeOffset: TimeInterval = 0, progress: ((_ t: Double) -> Void)? = nil) {
        guard let parent = node.parent else {
            preconditionFailure("Cannot move node without a parent.")
        }
        let oldParent = node.checkpoint?.parent
        node.checkpoint = GameElementNode.Checkpoint(parent: parent, moveAnimation: worldTransform)
        var enter: ((TimeDirection) -> Void)?
        var exit: ((TimeDirection) -> Void)?
        if oldParent != parent, let name = node.name, let node = node as? HideableNode {
            enter = { direction in
                switch direction {
                case .forward:
                    if (oldParent as? NodeParent)?.hideChildren == true && (parent as? NodeParent)?.hideChildren != true { // query hideChildren each time when running the animation, since it can change between runs when switching between players on the same device
                        node.show(name)
                    }
                case .backward:
                    if (oldParent as? NodeParent)?.hideChildren != true && (parent as? NodeParent)?.hideChildren == true {
                        node.show(name)
                    }
                }
            }
            exit = { direction in
                switch direction {
                case .forward:
                    if (oldParent as? NodeParent)?.hideChildren != true && (parent as? NodeParent)?.hideChildren == true {
                        node.hide()
                    }
                case .backward:
                    if (oldParent as? NodeParent)?.hideChildren == true && (parent as? NodeParent)?.hideChildren != true {
                        node.hide()
                    }
                }
            }
        }
        let progress = { (t: TimeInterval) in
            let transform = worldTransform(t)
            node.simdWorldPosition = transform.position
            node.simdWorldOrientation = transform.rotation
            progress?(t)
        }
        let timeline = GameSceneContext.current.timeline
        super.init(id: "MoveAnimation \(node.name ?? "nil")", subject: node, startTime: timeline.currentTime + timeline.timeOffset + timeOffset, duration: duration, enter: enter, progress: progress, exit: exit)
    }
    
    public convenience init(node: GameElementNode, path: Path = .linear, rotating: Rotation = .linear, timingMode: TimingMode = .easeInEaseOut, endTransform: Transform, duration: TimeInterval, timeOffset: TimeInterval = 0, progress: ((_ t: Double) -> Void)? = nil) {
        guard let parent = node.parent else {
            preconditionFailure("Cannot move node without a parent.")
        }
        if node.checkpoint == nil {
            node.initializeCheckpoint()
        }
        let checkpoint = node.checkpoint!
        let path = path.convert(from: parent, to: nil)
        let rotating = rotating.convert(from: parent, to: nil)
        let endTransform = parent.convertTransform(endTransform, to: nil)
        let transform = { (t: TimeInterval) -> Transform in
            let t = timingMode.apply(t: t)
            let startTransform = checkpoint.worldTransform
            let position = path.apply(start: startTransform.position, end: endTransform.position, t: t) // SCNNode.position is sometimes not reflected on screen (FB11968745, fixed in macOS 14.1 and iOS 17.1)
            let rotation = rotating.apply(start: startTransform.rotation, end: endTransform.rotation, t: t)
            return Transform(position: position, rotation: rotation)
        }
        self.init(node: node, worldTransform: transform, duration: duration, timeOffset: timeOffset, progress: progress)
    }
    
}
