import BoardGameKitHost
import SceneKit

@MainActor open class Scene3D: SCNNode {
    
    public struct HitTestResult {
        public let point: CGPoint
        public let hitTestResult: SCNHitTestResult
        public fileprivate(set) var sender: ButtonNode3D!
        public fileprivate(set) var descendants = [SCNNode]()
    }
    
    public static var current = Scene3D()
    nonisolated static let mainCamera = {
        let camera = SCNCamera()
        camera.zNear = 0.001
        camera.focalLength = 22
        let node = SCNNode()
        node.camera = camera
        return node
    }()
    
    public var allowsCameraControl = false
    
    private var touchedNode: ButtonNode3D?
    private var draggedNode: ButtonNode3D?
    private var cameraPanStartPosition: Vector3?
    private var uniformScale = 1.0
    private var minScale = 0.5
    private var maxScale = 5.0
    private var cameraPinchStartFocalLength: Double?
    private var aspectRatio = 1.6
    
    public func transition(to scene: Scene3D) {
        guard let parent = parent else {
            preconditionFailure()
        }
        runAction(.sequence([
            .fadeOut(duration: 0.2),
            .removeFromParentNode()
        ]))
        
        Scene3D.current = scene
        scene.opacity = 0
        scene.runAction(.fadeIn(duration: 0.2)) // transparent object is subtracted from scene instead of blending with it when parent node's opacity fades in from 0 (FB13645381)
        parent.addChildNode(scene)
    }
    
    open func layout() {
        let ratio = GameViewController.shared.view.frame.width / GameViewController.shared.view.frame.height
        let camera = Scene3D.mainCamera.camera!
        if ratio > aspectRatio && camera.projectionDirection != .vertical {
            camera.projectionDirection = .vertical
            camera.fieldOfView /= 1.44
            camera.focalLength *= uniformScale
        } else if ratio < aspectRatio && camera.projectionDirection != .horizontal {
            camera.projectionDirection = .horizontal
            camera.fieldOfView *= 1.44
            camera.focalLength *= uniformScale
        }
    }
    
    public func showError(_ error: any Error) {
        Scene2D.current.showError(error)
    }
    
    public func moveCamera(to transform: Transform) {
        Scene3D.mainCamera.runAction(.transform(transform, duration: 1).withTimingMode(.easeInEaseOut), forKey: "move")
    }
    
    // MARK: - Gestures
    
    public func hitTest(at point: CGPoint) -> HitTestResult? {
        guard let result = GameViewController.shared.scnView?.hitTest(point, options: [.searchMode: NSNumber(value: SCNHitTestSearchMode.closest.rawValue)]).first else {
            return nil
        }
        return HitTestResult(point: point, hitTestResult: result)
    }
    
    private func ancestors(of node: SCNNode, until: (SCNNode) -> Bool) -> [SCNNode] {
        var ancestors = [SCNNode]()
        var _node: SCNNode? = node
        while let node = _node {
            ancestors.append(node)
            if until(node) {
                break
            }
            _node = node.parent
        }
        return ancestors
    }
    
    open func tap(at point: CGPoint) {
        if let result = hitTest(at: point) {
            if case let ancestors = ancestors(of: result.hitTestResult.node, until: { ($0 as? ButtonNode3D).flatMap({ $0.isEnabled && $0.tap != nil }) == true }), let node = ancestors.last as? ButtonNode3D {
                var result = result
                result.sender = node
                result.descendants = Array(ancestors.reversed().dropFirst())
                node.tap!(result)
                return
            }
        }
        tapNothing()
    }
    
    open func tapNothing() {
    }
    
    open func longPressStart(at point: CGPoint) {
        if let result = hitTest(at: point) {
            if case let ancestors = ancestors(of: result.hitTestResult.node, until: { ($0 as? ButtonNode3D).flatMap({ $0.isEnabled && $0.longPress != nil }) == true }), let node = ancestors.last as? ButtonNode3D {
                var result = result
                result.sender = node
                result.descendants = Array(ancestors.reversed().dropFirst())
                touchedNode = node
                node.longPress!.start(result)
            }
        }
    }
    
    open func longPressEnd() {
        if let node = touchedNode {
            node.longPress?.end?(node)
            touchedNode = nil
        }
    }
    
    open func panStart(at point: CGPoint) {
        if let result = hitTest(at: point) {
            if case let ancestors = ancestors(of: result.hitTestResult.node, until: { ($0 as? ButtonNode3D).flatMap({ $0.isEnabled && $0.drag?.start != nil }) == true }), let node = ancestors.last as? ButtonNode3D {
                var result = result
                result.sender = node
                result.descendants = Array(ancestors.reversed().dropFirst())
                touchedNode = node
                draggedNode = dragNodeStart(result)
                return
            }
            #if os(iOS)
            if allowsCameraControl {
                cameraPanStartPosition = Scene3D.mainCamera.simdPosition
            }
            #endif
        }
    }
    
    open func dragNodeStart(_ result: Scene3D.HitTestResult) -> ButtonNode3D {
        return result.sender
    }
    
    open func panUpdate(at point: CGPoint, translation: CGPoint) {
        if let draggedNode = draggedNode {
            dragNode(draggedNode, to: point)
        } else if allowsCameraControl, let cameraPanStartPosition = cameraPanStartPosition {
            let translation = 0.0005 * CGPoint(x: -translation.x, y: translation.y)
            moveCamera(from: cameraPanStartPosition, by: translation)
        }
    }
    
    private func moveCamera(from: Vector3, by translation: CGPoint) {
        Scene3D.mainCamera.simdPosition = from + simd_quaternion(SCNNode.simdLocalFront, Vector3(x: Scene3D.mainCamera.simdWorldFront.x, y: 0, z: Scene3D.mainCamera.simdWorldFront.z)).act(Vector3(x: Float(translation.x), y: 0, z: Float(translation.y)))
    }
    
    open func dragNode(_ node: ButtonNode3D, to point: CGPoint) {
    }
    
    open func panEnd(translation: CGPoint, velocity: CGPoint) {
        if let touchedNode = touchedNode, let draggedNode = draggedNode {
            dropDraggedNode(draggedNode, sender: touchedNode)
        } else if allowsCameraControl {
            cameraPanStartPosition = nil
        }
        touchedNode = nil
        draggedNode = nil
    }
    
    open func dropDraggedNode(_ node: ButtonNode3D, sender: ButtonNode3D) {
    }
    
    public func startDrag(node: ButtonNode3D) {
        touchedNode = node
        draggedNode = node
    }
    
    public func endDrag() {
        if let touchedNode = touchedNode, let draggedNode = draggedNode {
            dropDraggedNode(draggedNode, sender: touchedNode)
        }
        touchedNode = nil
        draggedNode = nil
    }
    
    func pinchStart(at point: CGPoint, scale: Double) {
        guard allowsCameraControl else {
            return
        }
        cameraPinchStartFocalLength = Scene3D.mainCamera.camera!.focalLength
    }
    
    func pinchUpdate(scale: Double) {
        guard allowsCameraControl, let cameraPinchStartFocalLength = cameraPinchStartFocalLength else {
            return
        }
        #if os(macOS)
        var uniformScale = self.uniformScale + scale
        #else
        var uniformScale = self.uniformScale * scale
        #endif
        uniformScale = max(minScale, min(maxScale, uniformScale))
        Scene3D.mainCamera.camera!.focalLength = cameraPinchStartFocalLength * (uniformScale / self.uniformScale)
    }
    
    func pinchEnd(scale: Double) {
        #if os(macOS)
        var uniformScale = self.uniformScale + scale
        #else
        var uniformScale = self.uniformScale * scale
        #endif
        uniformScale = max(minScale, min(maxScale, uniformScale))
        self.uniformScale = uniformScale
        cameraPinchStartFocalLength = nil
    }
    
    #if os(macOS)
    open func mouseMoved(with event: NSEvent) {
        if let draggedNode = draggedNode {
            dragNode(draggedNode, to: GameViewController.shared.view.convert(event.locationInWindow, from: nil))
        }
    }
    
    func scrollStart(at point: CGPoint) {
        guard allowsCameraControl else {
            return
        }
        cameraPanStartPosition = Scene3D.mainCamera.simdPosition // SceneKit animation stutters while scrolling (FB14154584)
    }
    
    func scrollUpdate(translation: CGPoint) {
        guard allowsCameraControl, let cameraPanStartPosition = cameraPanStartPosition else {
            return
        }
        let translation = 0.0005 * translation
        moveCamera(from: cameraPanStartPosition, by: translation)
    }
    
    func scrollEnd(translation: CGPoint, velocity: CGPoint) {
        guard allowsCameraControl else {
            return
        }
        cameraPanStartPosition = nil
    }
    #endif
    
}
