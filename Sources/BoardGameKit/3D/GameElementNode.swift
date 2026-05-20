import BoardGameKitHost
import SceneKit

@MainActor open class GameElementNode: ButtonNode3D {
    
    public struct Checkpoint {
        let parent: SCNNode
        let moveAnimation: (_ t: TimeInterval) -> Transform
        
        @MainActor public var transform: Transform {
            return parent.convertTransform(moveAnimation(1), from: nil)
        }
        
        public var worldTransform: Transform {
            return moveAnimation(1)
        }
    }
    
    @Recorded public internal(set) var checkpoint: Checkpoint?
    
    public convenience init(geometry: SCNGeometry?) {
        self.init()
        self.geometry = geometry
    }
    
    public func initializeCheckpoint() {
        guard let parent = parent else {
            preconditionFailure("Cannot initialize checkpoint without a parent.")
        }
        let transform = parent.convertTransform(myTransform, to: nil)
        $checkpoint._wrappedValue = Checkpoint(parent: parent, moveAnimation: { _ in transform })
    }
    
    /// This drop point allows the player to cancel an action by dragging the node back to its original position. If dropping a node on any other point triggers a server action, then `action` will usually be `nil`. If on the other hand the player can drag nodes around without immediately triggering a server action, then `action` can be used to reset any state used to track the dragged nodes.
    public func identityDropPoint(action: ((ButtonNode3D) -> Void)? = nil) -> DropPoint {
        guard let parent = parent else {
            preconditionFailure("Node has no parent.")
        }
        return DropPoint(parent: parent, transform: myTransform, action: action ?? { _ in })
    }
    
    /// A temporary node that can be used during a drag operation instead of the original node.
    public func dragPlaceholder() -> GameElementNode {
        let node = GameElementNode(geometry: geometry)
        node.name = name
        node.myTransform = myTransform
        node.simdPivot = simdPivot
        node.opacity = 0.8
        for child in childNodes {
            node.addChildNode(child._dragPlaceholder())
        }
        return node
    }
    
}

@MainActor extension SCNNode {
    
    func _dragPlaceholder() -> SCNNode {
        let node = SCNNode(geometry: geometry)
        node.myTransform = myTransform
        for child in childNodes {
            node.addChildNode(child._dragPlaceholder())
        }
        return node
    }
    
    public func convertAndAddChildNode(_ child: GameElementNode) {
        convertAndInsertChildNode(child, at: child.parent == self ? childNodes.count - 1 : childNodes.count)
    }
    
    public func convertAndInsertChildNode(_ child: GameElementNode, at index: Int) {
        guard let oldParent = child.parent else {
            preconditionFailure("Node \(child.description) must already have a parent.")
        }
        if oldParent == self ? index >= childNodes.count : index > childNodes.count {
            preconditionFailure("Index \(index) beyond bounds for \(childNodes.count) child nodes of \(description).")
        }
        if child.checkpoint == nil {
            child.initializeCheckpoint()
        }
        child.transform = convertTransform(child.transform, from: oldParent)
        let oldIndex = oldParent.childNodes.firstIndex(of: child)!
        child.removeFromParentNode()
        
        oldParent.addUndoEvent(id: "Node.convertAndInsertChildNode \(child.name ?? "nil")") { parent in
            parent.convertAndInsertChildNode(child, at: oldIndex)
        }
        insertChildNode(child, at: index)
    }
    
}
