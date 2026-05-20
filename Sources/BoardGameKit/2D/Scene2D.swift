import BoardGameKitHost
import SpriteKit

open class Scene2D: SKNode, ServerDelegate {
    
    public struct HitTestResult {
        public let node: SKNode
        public let point: CGPoint
        public fileprivate(set) var sender: ButtonNode2D!
        public fileprivate(set) var descendants = [SKNode]()
    }
    
    public static var current: Scene2D = LaunchScene()
    
    var isEnabled = false
    public private(set) var sceneFrame = CGRect.zero
    #if os(iOS)
    private var safeAreaInsets = UIEdgeInsets.zero
    #endif
    public private(set) var unsafeSceneFrame = CGRect.zero
    public private(set) var viewFrame = CGRect.zero
    
    private var handles = [String: (Data) throws -> Void]()
    private var touchedNode: SKNode?
    private var draggedNode: ButtonNode2D?
    
    open func willAppear() {
    }
    
    open func transition(to scene: Scene2D) {
        isEnabled = false
        scene.willAppear()
        Scene2D.current = scene
        #if os(iOS)
        scene.safeAreaInsets = GameViewController.shared.view.safeAreaInsets
        #endif
        scene.viewSize = GameViewController.shared.view.frame.size
        
        GameViewController.shared.updateSpriteKit { [self] in
            guard let parent = parent else {
                preconditionFailure()
            }
            zPosition = 0
            run(.sequence([
                .fadeOut(withDuration: 0.2),
                .run { [weak self] in
                    Task { @MainActor in
                        self?.removeFromParent() // SKAction.removeFromParent() causes crash when run in SCNView.overlaySKScene (FB15498049)
                    }
                }
            ]))
            
            scene.zPosition = -1
            scene.alpha = 0
            scene.run(.fadeIn(withDuration: 0.2)) {
                Task { @MainActor in
                    scene.isEnabled = true
                }
            }
            parent.addChild(scene)
            scene.layout()
        }
        #if os(macOS)
        GameViewController.shared.scnView?.needsDisplay = true // SceneKit overlay view is not drawn until performing scroll gesture (FB14155213)
        #else
        GameViewController.shared.scnView?.setNeedsDisplay() // SceneKit overlay view is not drawn until performing scroll gesture (FB14155213)
        #endif
    }
    
    open override var frame: CGRect {
        return CGRect(x: 0, y: 0, width: 800, height: 400)
    }
    
    var viewSize = CGSize.zero {
        didSet {
            let scale = min(viewSize.width / frame.width, viewSize.height / frame.height, 1)
            viewFrame = CGRect.zero.insetBy(dx: -viewSize.width / 2, dy: -viewSize.height / 2)
            sceneFrame = viewFrame
            #if os(iOS)
            sceneFrame.origin.x += safeAreaInsets.left
            sceneFrame.size.width -= safeAreaInsets.left + safeAreaInsets.right
            sceneFrame.origin.y += safeAreaInsets.bottom
            sceneFrame.size.height -= safeAreaInsets.top + safeAreaInsets.bottom
            #endif
            sceneFrame = sceneFrame.applying(.init(scaleX: 1 / scale, y: 1 / scale))
            unsafeSceneFrame = viewFrame.applying(.init(scaleX: 1 / scale, y: 1 / scale))
            setScale(scale) // SCNView.overlaySKScene.setScale doesn't work (FB14930422)
        }
    }
    
    open func layout() {
        scene?.size = viewSize
    }
    
    public func showError(_ error: any Error) {
        GameViewController.shared.showError(error)
    }
    
    // MARK: - Server
    
    public func server(_ server: Server, handleError error: any Error) {
        showError(error)
        isEnabled = true
    }
    
    public func serverDidConnect(_ server: Server) {
    }
    
    public func serverDidDisconnect(_ server: Server) {
        transition(to: ClientConfiguration.shared.scenes.mainMenu.init())
        Scene2D.current.serverDidDisconnect(server)
    }
    
    public func server(_ server: Server, didReceiveRequest request: RawRequest) {
        handle(event: request)
    }
    
    public func serverShouldReinvitePlayer(_ server: any Server) -> Bool {
        return true
    }
    
    public func send<T: Request>(_ data: T) {
        ServerShared.send(data)
    }
    
    public func addHandle<T: Request>(_ handle: @escaping (_ data: T) throws -> Void) {
        if handles.updateValue({ data in
            let request = try RequestCoder.decode(T.self, from: data)
            try handle(request)
        }, forKey: T.name) != nil {
            preconditionFailure("Handle \(T.name) is already registered.")
        }
    }
    
    public func removeAllHandles() {
        handles.removeAll()
    }
    
    func handle(event: RawRequest) {
        Logger.shared.debug("Handle event \(event.name)")
        if let handle = handles[event.name] {
            do {
                try handle(event.data)
            } catch {
                fatalError("Error during handling of event \(event.prettyPrinted)\n\(error.localizedDescription)")
            }
        } else {
            fatalError("Unhandled event \(event.name) in \(String(describing: type(of: self))).")
        }
    }
    
    // MARK: - Gestures
    
    func hitTest(at point: CGPoint) -> HitTestResult? {
        if !isEnabled {
            return nil
        }
        #if os(macOS)
        GameViewController.shared.scnView?.needsDisplay = true // SceneKit overlay view is not drawn until performing scroll gesture (FB14155213)
        #else
        GameViewController.shared.scnView?.setNeedsDisplay() // SceneKit overlay view is not drawn until performing scroll gesture (FB14155213)
        #endif
        let point = scene!.convertPoint(fromView: point)
        let node = scene!.atPoint(point) // SKNode.atPoint(_;) returns descendant of SKCropNode that is not visible at the given point (FB14919849)
        return node != scene && node != self ? HitTestResult(node: node, point: point) : nil
    }
    
    private func ancestors(of node: SKNode, until: (SKNode) -> Bool) -> [SKNode] {
        var ancestors = [SKNode]()
        var _node: SKNode? = node
        while let node = _node {
            ancestors.append(node)
            if until(node) {
                break
            }
            _node = node.parent
        }
        return ancestors
    }
    
    func tap(_ result: HitTestResult) {
        if case let ancestors = ancestors(of: result.node, until: { ($0 as? ButtonNode2D).flatMap({ $0.tap != nil }) == true }), let node = ancestors.last as? ButtonNode2D {
            if node.isEnabled {
                var result = result
                result.sender = node
                result.descendants = Array(ancestors.reversed().dropFirst())
                node.tap!(result)
            } else if let sound = ClientConfiguration.shared.theme.disabledButtonTapSoundPath {
                PreparedResources.sound(named: sound).currentTime = 0
                PreparedResources.sound(named: sound).play()
            }
        }
    }
    
    func panStart(_ result: HitTestResult) {
        if case let ancestors = ancestors(of: result.node, until: { $0 is ScrollView }), let scrollView = ancestors.last as? ScrollView {
            touchedNode = scrollView
            scrollView.panStart()
        } else if case let ancestors = ancestors(of: result.node, until: { ($0 as? ButtonNode2D).flatMap({ $0.isEnabled && $0.drag?.start != nil }) == true }), let node = ancestors.last as? ButtonNode2D {
            touchedNode = node
            draggedNode = dragNodeStart(node)
        }
    }
    
    func panUpdate(at point: CGPoint, translation: CGPoint) {
        let point = scene!.convertPoint(fromView: point)
        if let scrollView = touchedNode as? ScrollView {
            scrollView.panUpdate(withTranslation: translation)
        } else if let draggedNode = draggedNode {
            dragNode(draggedNode, to: point)
        }
    }
    
    func panEnd(translation: CGPoint, velocity: CGPoint) {
        if let scrollView = touchedNode as? ScrollView {
            scrollView.panEnd(withTranslation: translation, velocity: velocity)
        } else if let node = touchedNode as? ButtonNode2D, let draggedNode = draggedNode {
            dropDraggedNode(draggedNode, sender: node)
        }
        touchedNode = nil
        draggedNode = nil
    }
    
    func dragNodeStart(_ node: ButtonNode2D) -> ButtonNode2D {
        return node.drag!.start(node)
    }
    
    func dragNode(_ node: ButtonNode2D, to point: CGPoint) {
        node.drag?.update?(node, point)
    }
    
    func dropDraggedNode(_ node: ButtonNode2D, sender: ButtonNode2D) {
        sender.drag?.end?(node)
    }
    
    func pinchStart(_ result: HitTestResult, scale: Double) {
    }
    
    func pinchUpdate(scale: Double) {
    }
    
    func pinchEnd(scale: Double) {
    }
    
    #if os(macOS)
    func scrollStart(_ result: HitTestResult) {
        if case let ancestors = ancestors(of: result.node, until: { $0 is ScrollView }), let scrollView = ancestors.last as? ScrollView {
            touchedNode = scrollView
            scrollView.panStart()
        }
    }
    
    func scrollUpdate(translation: CGPoint) {
        if let scrollView = touchedNode as? ScrollView {
            scrollView.panUpdate(withTranslation: translation)
        }
    }
    
    func scrollEnd(translation: CGPoint, velocity: CGPoint) {
        if let scrollView = touchedNode as? ScrollView {
            scrollView.panEnd(withTranslation: translation, velocity: velocity)
            touchedNode = nil
        }
    }
    #endif
    
}
