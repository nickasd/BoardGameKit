import BoardGameKitHost
import SceneKit

@MainActor public protocol NodeParent: SCNNode {
    var hideChildren: Bool { get }
    func animateNodes(timeOffset: TimeInterval, duration: TimeInterval)
}

extension NodeParent {
    
    public func animateNodes(timeOffset: TimeInterval = 0, duration: TimeInterval = 0) {
        animateNodes(timeOffset: timeOffset, duration: duration)
    }
    
}

/**
 A protocol implemented by nodes that can hide and show private information.
 
 When adding nodes to a parent that shows or hides its children at the end of the animation, make sure that the nodes don't participate in other animations before the first one has completed. Otherwise you may end up showing a node at the begin of an animation that should happen later chronologically, only to hide it again at the end of the previous animation that erroneously overlaps the next one, causing the node to remain hidden even it if should be visible.
 */
@MainActor public protocol HideableNode: SCNNode {
    func show(_ name: String)
    func hide()
}

/// A `NodeGroup` defines the transforms of its child nodes. Child nodes are initially added with `initialize(_:)`, then converted between node groups with one of the `appendNewNode` or `insertNewNode` methods and animated to their new transforms by calling `animateNodes()`.
public class NodeGroup<Element: GameElementNode>: GameElementNode, NodeParent {
    
    /// The default animation duration that is used when animating added nodes to their final position with `animateNodes()`.
    public var animationDuration = TimeInterval(1)
    /// The default animation path that is used when animating added nodes to their final position with `animateNodes()`.
    public var animationPath = MoveAnimation.Path.alongControlPoint(Vector3(x: 0, y: 0.1, z: 0))
    /// The default animation rotation that is used when animating added nodes to their final position with `animateNodes()`.
    public var animationRotation = MoveAnimation.Rotation.linear
    /// The default animation timing mode that is used when animating added nodes to their final position with `animateNodes()`.
    public var animationTimingMode = MoveAnimation.TimingMode.easeInEaseOut
    /// A function that determines the order of child nodes during animations: a node name with a lower weight is ordered before a node name with a higher weight. You can change the weight during the game inside the block passed to `GameScene3D.updateAllAnimations(_:)`, which affects future as well as past animations.
    public var childOrder: ((_ name: String) -> Int)? {
        didSet {
            childOrderVersion += 1
        }
    }
    private var childOrderVersion = 0
    /// Child nodes must implement the `HideableNode` protocol so that their `show(_:)` and `hide()` methods can be called at appropriate times.
    public var hideChildren = false {
        didSet {
            if hideChildren != oldValue {
                showOrHideChildren()
            }
        }
    }
    /// Child nodes that have been added through one of the `appendNewNode` or `insertNewNode` methods. Calling `animateNodes()` resets the array again.
    public internal(set) var newNodes = [Element]()
    /// Child nodes that have been selected through `toggleSelectedNode(_:)`.
    public private(set) var selectedNodes = [Element]()
    
    public func transform(ofChildAt index: Int) -> Transform {
        fatalError("transform(ofChildAt:) has not been implemented.")
    }
    
    /// Adds and initializes the given `nodes` by setting their transform.
    public func initialize<S: Sequence>(_ nodes: S) where S.Element == Element {
        for node in nodes {
            addChildNode(node)
        }
        for (i, node) in nodes.enumerated() {
            node.myTransform = transform(ofChildAt: i) // setting SCNNode.eulerAngles has no effect when adding a node right afterwards (FB9952017, fixed in macOS 14?)
        }
    }

    // MARK: - Get elements
    
    public func childNodes() -> [Element] {
        return childNodes as! [Element]
    }
    
    public var firstChildNode: Element? {
        return childNodes.first as? Element
    }
    
    public func firstChildNodes(count: Int) -> [Element] {
        if count > childNodes.count {
            preconditionFailure("requesting first \(count) childNodes, but has only \(childNodes.count).")
        }
        var nodes = [Element]()
        for i in 0..<count {
            nodes.append(childNodes[i] as! Element) // EXC_BAD_ACCESS exception on SCNNode.addChildNode() when using childNodes[0..<] (FB9048570, fixed in macOS 14?)
        }
        return nodes
    }
    
    public var lastChildNode: Element? {
        return childNodes.last as? Element
    }
    
    public func lastChildNodes(count: Int) -> [Element] {
        if count > childNodes.count {
            preconditionFailure("Requested last \(count) childNodes, but has only \(childNodes.count).")
        }
        var nodes = [Element]()
        for i in 0..<count {
            nodes.append(childNodes[childNodes.count - 1 - i] as! Element) // EXC_BAD_ACCESS exception on SCNNode.addChildNode() when using childNodes[0..<] (FB9048570, fixed in macOS 14?)
        }
        return nodes
    }
    
    /// Returns the first child node, setting its name to `nil`.
    public func firstChildNodeHidden() -> Element {
        return firstChildNodesHidden(count: 1)[0]
    }
    
    /// Returns the first `count` child nodes, setting their names to `nil`.
    public func firstChildNodesHidden(count: Int) -> [Element] {
        let nodes = firstChildNodes(count: count)
        setNames(nodes.map({ NameChange(node: $0, name: nil) }))
        return nodes
    }

    /// Returns the last child node, setting its name to `nil`.
    public func lastChildNodeHidden() -> Element {
        return lastChildNodes(hiddenCount: 1)[0]
    }
    
    /// Returns the last `count` child nodes, setting their names to `nil`.
    public func lastChildNodes(hiddenCount count: Int) -> [Element] {
        let nodes = lastChildNodes(count: count)
        setNames(nodes.map({ NameChange(node: $0, name: nil) }))
        return nodes
    }
    
    /// Requests the first child node with the given `name`. If it doesn't exist, finds the first child without a name, sets its new name and returns it, otherwise throws an exception.
    public func firstChildNode(withName name: String) -> Element {
        return firstChildNodes(withNames: [name])[0]
    }
    
    /// Requests the first child nodes with the given `names`. If a child doesn't exist, finds the first remaining child without a name and sets its new name, otherwise throws an exception.
    public func firstChildNodes(withNames names: [String]) -> [Element] {
        var allNodes = childNodes()
        var nodes = [Element]()
        var nameChanges = [NameChange]()
        for name in names {
            if let index = allNodes.firstIndex(where: { $0.name == name }) {
                nodes.append(allNodes.remove(at: index))
            } else if let index = allNodes.firstIndex(where: { $0.name == nil }) {
                let node = allNodes.remove(at: index)
                nodes.append(node)
                nameChanges.append(NameChange(node: node, name: name))
            } else {
                preconditionFailure("Child node with name \(name) doesn't exist and neither does a node without a name.")
            }
        }
        setNames(nameChanges)
        return nodes
    }
    
    /// Requests the last child node with the given `name`. If it doesn't exist, finds the last child without a name, sets its new name and returns it, otherwise throws an exception.
    public func lastChildNode(withName name: String) -> Element {
        return lastChildNodes(withNames: [name])[0]
    }
    
    /// Requests the last child nodes with the given `names`. If a child doesn't exist, looks for the last remaining child without a name and sets its new name, otherwise throws an exception.
    public func lastChildNodes(withNames names: [String]) -> [Element] {
        var allNodes = childNodes()
        var nodes = [Element]()
        var nameChanges = [NameChange]()
        for name in names {
            if let index = allNodes.lastIndex(where: { $0.name == name }) {
                nodes.append(allNodes.remove(at: index))
            } else if let index = allNodes.lastIndex(where: { $0.name == nil }) {
                let node = allNodes.remove(at: index)
                nodes.append(node)
                nameChanges.append(NameChange(node: node, name: name))
            } else {
                preconditionFailure("Child node with name \(name) doesn't exist and neither does a node without a name.")
            }
        }
        setNames(nameChanges)
        return nodes
    }
    
    public struct NameChange {
        let node: Element
        let name: String?
        
        public init(node: Element, name: String?) {
            self.node = node
            self.name = name
        }
    }
    
    /// Assigns the given `names` to the given `nodes`. This method supports undo operations.
    public func setNames<S: Collection>(_ nameChanges: S) where S.Element == NameChange {
        if nameChanges.isEmpty {
            return
        }
        let oldNames = nameChanges.map({ NameChange(node: $0.node, name: $0.node.name) })
        for nameChange in nameChanges {
            nameChange.node.name = nameChange.name
        }
        
        if let undoManager = GameContext.current.undoManager, undoManager.groupingLevel > 0 {
            addUndoEvent(id: "NodeGroup.setNames") { nodeGroup in
                nodeGroup.setNames(oldNames)
            }
        }
    }
    
    // MARK: - Add and insert elements
    
    /**
     Adds the given `node`, preserving its current world transform.
     
     This method records whether the node is moved between parents that have a different value of `hideChildren`. If this is the case, then the node must conform to `HideableNode`. When animating the node to its final transform with `animateNodes()`, the node's `show(_:)` or `hide()` method is called at the beginning or the end of the animation, respectively.
     */
    public func appendNewNode(_ node: Element) {
        appendNewNodes([node])
    }
    
    /**
     Adds the given `nodes`, preserving their current world transforms.

     This method records whether the nodes are moved between parents that have a different value of `hideChildren`. If this is the case, then the nodes must conform to `HideableNode`. When animating the nodes to their final transforms with `animateNodes()`, each node's `show(_:)` or `hide()` method is called at the beginning or the end of the animation, respectively.
     */
    public func appendNewNodes<S: Sequence>(_ nodes: S) where S.Element == Element {
        insertNewNodes(nodes, atOffsets: IndexSet(nodes.enumerated().map({ childNodes.count + $0.offset })))
    }
    
    /**
     Inserts the given `node` at the given `index`, preserving its current world transform.
     
     This method records whether the node is moved between parents that have a different value of `hideChildren`. If this is the case, then the node must conform to `HideableNode`. When animating the node to its final transform with `animateNodes()`, the node's `show(_:)` or `hide()` method is called at the beginning or the end of the animation, respectively.
     */
    public func insertNewNode(_ node: Element, at index: Int) {
        insertNewNodes([node], atOffsets: [index])
    }
    
    /**
     Inserts the given `nodes` at the given `offsets`, preserving their current world transforms.
     
     This method records whether the nodes are moved between parents that have a different value of `hideChildren`. If this is the case, then the nodes must conform to `HideableNode`. When animating the nodes to their final transforms with `animateNodes()`, each node's `show(_:)` or `hide()` method is called at the beginning or the end of the animation, respectively.
     */
    public func insertNewNodes<S: Sequence>(_ nodes: S, atOffsets offsets: IndexSet) where S.Element == Element {
        newNodes.append(contentsOf: nodes)
        for (node, index) in zip(nodes, offsets) {
            convertAndInsertChildNode(node, at: index)
        }
    }
    
    // MARK: - Animation
    
    private class VersionedArray {
        
        var elements: [Element]
        var orderVersion = 0
        
        init(elements: [Element]) {
            self.elements = elements
        }
        
    }
    
    /// Animates the child nodes to their final position. If the child nodes are instances of `NodeGroup`, calls `animateNodes()` recursively.
    public func animateNodes(timeOffset: TimeInterval, duration: TimeInterval) {
        for node in childNodes {
            node.removeAction(forKey: "move")
        }
        let duration = duration <= 0 ? animationDuration : duration
        if let childNodes = childNodes as? [NodeParent] {
            for (i, node) in childNodes.enumerated() {
                node.animateNodes(timeOffset: timeOffset + TimeInterval(i) / TimeInterval(childNodes.count) * duration, duration: duration)
            }
        } else if childOrder != nil, case let names = childNodes.compactMap({ $0.name }), names.count == childNodes.count {
            let childNodes = childNodes()
            let sortedChildNodes = VersionedArray(elements: childNodes)
            let transforms = childNodes.indices.map({ convertTransform(transform(ofChildAt: $0), to: nil) })
            let newNodes = newNodes
            for node in childNodes {
                if node.checkpoint == nil {
                    node.initializeCheckpoint()
                }
                let checkpoint = node.checkpoint!
                let animationPath = animationPath.convert(from: self, to: nil)
                let animationRotation = animationRotation.convert(from: self, to: nil)
                let index = newNodes.firstIndex(of: node)
                addAnimation(MoveAnimation(node: node, worldTransform: { [self] t in
                    if let childOrder = childOrder, childOrderVersion != sortedChildNodes.orderVersion {
                        let weights = names.map({ childOrder($0) })
                        sortedChildNodes.elements = childNodes.enumerated().sorted(by: { weights[$0.offset] < weights[$1.offset] }).map({ $0.element })
                        sortedChildNodes.orderVersion = childOrderVersion
                    }
                    let i = sortedChildNodes.elements.firstIndex(of: node)!
                    let newTransform = transforms[i]
                    if t == 1 {
                        return newTransform
                    }
                    let oldTransform = checkpoint.worldTransform
                    if let index = index {
                        let subDuration = duration / (log10(TimeInterval(newNodes.count)) + 1)
                        let timeOffset = TimeInterval(index) / TimeInterval(newNodes.count) * (duration - subDuration)
                        let range = (timeOffset / duration)...((timeOffset + subDuration) / duration)
                        var t = max(0, min((t - range.lowerBound) / (range.upperBound - range.lowerBound), 1))
                        t = animationTimingMode.apply(t: t)
                        return Transform(position: animationPath.apply(start: oldTransform.position, end: newTransform.position, t: t), rotation: animationRotation.apply(start: oldTransform.rotation, end: newTransform.rotation, t: t), scale: .one)
                    } else if newTransform != oldTransform {
                        let subDuration = duration * 0.4
                        let timeOffset = TimeInterval(i) / TimeInterval(childNodes.count) * subDuration
                        let range = (timeOffset / duration)...((timeOffset + subDuration) / duration)
                        var t = max(0, min((t - range.lowerBound) / (range.upperBound - range.lowerBound), 1))
                        t = animationTimingMode.apply(t: t)
                        return Transform(position: MoveAnimation.Path.linear.apply(start: oldTransform.position, end: newTransform.position, t: t), rotation: MoveAnimation.Rotation.linear.apply(start: oldTransform.rotation, end: newTransform.rotation, t: t), scale: .one)
                    } else {
                        return oldTransform
                    }
                }, duration: duration, timeOffset: timeOffset))
            }
        } else {
            for (i, node) in childNodes().enumerated() {
                let transform = transform(ofChildAt: i)
                if let index = newNodes.firstIndex(of: node) {
                    let subDuration = duration / (log10(TimeInterval(newNodes.count)) + 1)
                    addAnimation(MoveAnimation(node: node, path: animationPath, rotating: animationRotation, timingMode: animationTimingMode, endTransform: transform, duration: subDuration, timeOffset: timeOffset + TimeInterval(index) / TimeInterval(newNodes.count) * (duration - subDuration)))
                } else if node.checkpoint?.parent != self || node.checkpoint?.transform != transform {
                    let duration = duration * 0.4
                    addAnimation(MoveAnimation(node: node, endTransform: transform, duration: duration, timeOffset: timeOffset + TimeInterval(i) / TimeInterval(childNodes.count) * duration))
                }
            }
        }
        self.newNodes.removeAll()
    }
    
    private func showOrHideChildren() {
        for node in childNodes.compactMap({ $0 as? HideableNode }) {
            guard let name = node.name else {
                fatalError("\(description) cannot show a node without a name.")
            }
            if hideChildren {
                node.hide()
            } else {
                node.show(name)
            }
        }
    }
    
    // MARK: - Selection
    
    public override var isEnabled: Bool {
        didSet {
            if !isEnabled {
                deselectAllNodes()
            }
        }
    }
    
    /// Deselects the given `node` if it is selected, otherwise selects it.
    public func toggleSelectedNode(_ node: Element) {
        let selectionIndex = selectedNodes.firstIndex(of: node)
        guard childNodes().contains(node) else {
            preconditionFailure("Selected node \(node.description) is not a child node.")
        }
        if let selectionIndex = selectionIndex {
            selectedNodes.remove(at: selectionIndex)
            node.highlight(false)
        } else {
            selectedNodes.append(node)
            node.highlight(true)
        }
    }
    
    /// Deselects all nodes, moving them back to their respective original positions.
    public func deselectAllNodes() {
        for node in selectedNodes {
            node.highlight(false)
        }
        selectedNodes.removeAll()
    }
    
}

public class FixedNodeGroup<Element: GameElementNode>: NodeGroup<Element> {
    
    public let childTransforms: [Transform]

    /// Child nodes are placed and rotated according to the given `childTransforms`. If the number of child nodes exceeds the length of the array, throws a runtime error.
    public init(childTransforms: [Transform]) {
        self.childTransforms = childTransforms
        super.init()
    }
    
    /// Child nodes are placed at the given `childPositions`. If the number of child nodes exceeds the length of the array, throws a runtime error.
    public convenience init(childPositions: [Vector3], rotation: Rotation = .identity) {
        self.init(childTransforms: childPositions.map({ Transform(position: $0, rotation: rotation) }))
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func transform(ofChildAt index: Int) -> Transform {
        if !childTransforms.indices.contains(index) {
            fatalError("Invalid index \(index) for provided childTransforms (\(childTransforms.count)).")
        }
        return childTransforms[index]
    }
    
}

public class RecordedFixedNodeGroup<Element: GameElementNode>: NodeGroup<Element> {
    
    public var childTransforms: RecordedArray<Transform>
    
    /// Child nodes are placed and rotated according to the given `childTransforms`. If the number of child nodes exceeds the length of the array, throws a runtime error.
    public init(childTransforms: [Transform]) {
        self.childTransforms = RecordedArray(childTransforms)
        super.init()
    }
    
    /// Child nodes are placed at the given `childPositions`. If the number of child nodes exceeds the length of the array, throws a runtime error.
    public convenience init(childPositions: [Vector3], rotation: Rotation = .identity) {
        self.init(childTransforms: childPositions.map({ Transform(position: $0, rotation: rotation) }))
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func transform(ofChildAt index: Int) -> Transform {
        if index >= childTransforms.count {
            fatalError("Provided childPositions (\(childTransforms.count)) do not match child count (\(childNodes.count)).")
        }
        return childTransforms[index]
    }
    
}

public class NodeGrid<Element: GameElementNode>: NodeGroup<Element> {
    
    public var horizontalDistance: Vector3
    public var horizontalCount: Int
    public var verticalDistance: Vector3
    public var center: Bool
    public var childRotation = Rotation.identity

    /// Child nodes are spaced at `horizontalDistance` from one another. When the number of children reaches `horizontalCount`, the following ones are placed on a new line at `verticalDistance` from the first one, and so on. If `center` is `false` (the default), the first child is placed at the origin of the node; if it is `true`, the grid of children is centered on the node's origin.
    public init(horizontalDistance: Vector3, horizontalCount: Int, verticalDistance: Vector3, center: Bool = false) {
        self.horizontalDistance = horizontalDistance
        self.horizontalCount = horizontalCount
        self.verticalDistance = verticalDistance
        self.center = center
        super.init()
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func transform(ofChildAt index: Int) -> Transform {
        let start: Vector3
        if center {
            let row = index / horizontalCount
            let columns = min(childNodes.count, (row + 1) * horizontalCount) - row * horizontalCount
            let rows = childNodes.count / horizontalCount
            start = -Float(columns - 1) / 2 * horizontalDistance - Float(rows - 1) / 2 * verticalDistance
        } else {
            start = Vector3()
        }
        let horizontal = Float(index % horizontalCount) * horizontalDistance
        let vertical = Float(index / horizontalCount) * verticalDistance
        return Transform(position: start + horizontal + vertical, rotation: childRotation) // "import SceneKit" causes project compile time to increase by almost 800%
    }
    
}

public class NodeArray<Element: GameElementNode>: NodeGroup<Element> {
    
    public var distance: Vector3
    public var center: Bool
    public var childRotation = Rotation.identity
    
    /// Child nodes are spaced at `distance` from one another. If `center` is `false` (the default), the first child is placed at the origin of the node; if it is `true`, the array of children is centered on the node's origin.
    public init(distance: Vector3, center: Bool = false) {
        self.distance = distance
        self.center = center
        super.init()
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func transform(ofChildAt index: Int) -> Transform {
        let start = center ? -Float(childNodes.count - 1) / 2 * distance : .zero
        return Transform(position: start + Float(index) * distance, rotation: childRotation)
    }
    
    public func transformForAddingDraggedNode() -> Transform {
        return transformForInsertingDraggedNode(at: childNodes.count)
    }
    
    public func transformForInsertingDraggedNode(at index: Int) -> Transform {
        let start = center ? -Float(childNodes.count - 1) / 2 * distance : .zero
        let indexOffset: Float = if childNodes.isEmpty || index == childNodes.count {
            0
        } else if index == 0 {
            -1
        } else {
            -0.5
        }
        return Transform(position: start + (Float(index) + indexOffset) * distance, rotation: childRotation)
    }
    
}

public class NodeCircle<Element: GameElementNode>: NodeGroup<Element> {
    
    public var radius: Vector3
    public var normal: Vector3
    /// If `childRotation` is `nil`, child nodes are rotated along the `normal` according to the angle at which they are placed. Otherwise, the given value is used for all children.
    public var childRotation: Rotation? = .identity

    /// Child nodes are placed along a circle with the given `radius` and `normal`. If the node contains only a single child, it is placed at the center. `normal` should be a vector of length 1.
    public init(radius: Vector3, normal: Vector3) {
        self.radius = radius
        self.normal = normal
        super.init()
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func transform(ofChildAt index: Int) -> Transform {
        if childNodes.count == 1 {
            return Transform(position: .zero, rotation: rotation(at: 0))
        } else {
            let angle = Float(index) / Float(childNodes.count) * 2 * .pi
            let position = Vector3(simd_quaternion(angle, normal).act(radius))
            return Transform(position: position, rotation: rotation(at: angle))
        }
    }
    
    private func rotation(at angle: Float) -> Rotation {
        childRotation ?? Rotation(angle: angle, axis: normal)
    }
    
    public func transformForAddingDraggedNode() -> Transform {
        return if childNodes.count == 1 {
            Transform(position: radius, rotation: rotation(at: 0))
        } else {
            Transform(position: .zero, rotation: rotation(at: 0))
        }
    }
    
}

public class NodeSphere<Element: GameElementNode>: NodeGroup<Element> {
    
    public var radius: Vector3
    
    /// Child nodes are placed on the surface of a sphere with the given `radius`, looking towards the sphere center. The rotation of the node itself is set according to the direction of the vector.
    public init(radius: Vector3) {
        self.radius = radius
        super.init()
        simdOrientation = Rotation(from: SCNNode.simdLocalUp, to: simd_normalize(radius))
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func transform(ofChildAt index: Int) -> Transform {
        let index = Float(index)
        let scalar = Float(simd_length(radius))
        let y = 1 - (index / Float(childNodes.count - 1)) * 2
        let circleRadius = (1 - y * y).squareRoot()
        let phi = Double.pi * (3 - 5.squareRoot())
        let theta = Float(phi) * index
        let position = scalar * Vector3(x: cos(theta) * circleRadius, y: y, z: sin(theta) * circleRadius)
        let rotation = Rotation(lookingFrom: .zero, to: position)
        return Transform(position: position, rotation: rotation)
    }
    
}

public class NodeDeck<Element: GameElementNode>: NodeArray<Element> {
    
    private var addedBelow = false
    
    public init(distance: Vector3) {
        super.init(distance: distance)
        animationPath = .alongControlPoint(Vector3(x: 0, y: 0.2, z: 0.2))
        hideChildren = true
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override var hideChildren: Bool {
        didSet {
            childRotation = Rotation(x: 0, y: 0, z: hideChildren ? .pi : 0)
        }
    }
    
    public override func transform(ofChildAt index: Int) -> Transform {
        return super.transform(ofChildAt: index) + Vector3(x: 0, y: distance.y, z: 0)
    }
    
    public func addAbove<S: Sequence>(_ nodes: S) where S.Element == Element {
        appendNewNodes(nodes)
    }
    
    public func addBelow<S: Sequence>(_ nodes: S) where S.Element == Element {
        let indices = IndexSet(nodes.enumerated().map({ $0.offset }))
        insertNewNodes(nodes, atOffsets: indices)
        addedBelow = !indices.isEmpty
    }
    
    /// Unlike other node groups, a node deck's `animateNodes()` method doesn't just create the animations, but also resets the names of all added nodes to `nil`.
    public override func animateNodes(timeOffset: TimeInterval = 0, duration: TimeInterval = 0) {
        let newNodes = newNodes
        if addedBelow {
            let duration = duration <= 0 ? animationDuration : duration
            for (i, node) in childNodes().enumerated() {
                let transform = transform(ofChildAt: i)
                if let index = newNodes.firstIndex(of: node) {
                    addAnimation(MoveAnimation(node: node, path: animationPath, rotating: animationRotation, timingMode: animationTimingMode, endTransform: transform, duration: duration, timeOffset: timeOffset + TimeInterval(index) / TimeInterval(newNodes.count) * duration))
                } else {
                    addAnimation(MoveAnimation(node: node, path: .throughPoint(transform.position + Vector3(x: 0, y: 0.05, z: 0)), endTransform: transform, duration: duration * 2, timeOffset: timeOffset))
                }
            }
            self.newNodes.removeAll()
            addedBelow = false
        } else {
            super.animateNodes(timeOffset: timeOffset, duration: duration)
        }
        setNames(newNodes.map({ NameChange(node: $0, name: nil) }))
    }
    
}

public class NodeDiscardPile<Element: GameElementNode>: NodeArray<Element> {
    
    public override var hideChildren: Bool {
        didSet {
            childRotation = Rotation(x: hideChildren ? -.pi : 0)
        }
    }
    
    public func transformForDiscardingDraggedNode(_ node: Element) -> Transform {
        return Transform(position: (Float(childNodes.count) - 0.5) * distance + childRotation.act(Vector3(x: 0, y: 0, z: hideChildren ? -0.01 : 0.01)), rotation: childRotation)
    }
    
}

public class NodeStack<Element: GameElementNode>: NodeArray<Element> {
    
    public init(distance: Vector3) {
        super.init(distance: distance)
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    

}

public class NodeVanisher<Element: GameElementNode>: NodeGroup<Element> {
    
    public override func animateNodes(timeOffset: TimeInterval, duration: TimeInterval) {
        let duration = duration <= 0 ? animationDuration : duration
        for (i, node) in newNodes.enumerated() {
            addAnimation(MoveAnimation(node: node, endTransform: (node.checkpoint.map({ convertTransform($0.transform, from: $0.parent) }) ?? node.myTransform) + Vector3(x: 0, y: 0.05, z: 0), duration: duration, timeOffset: timeOffset + TimeInterval(i) / TimeInterval(newNodes.count) * duration, progress: { t in
                node.opacity = CGFloat(1 - t)
            }))
        }
        newNodes.removeAll()
    }
    
}
