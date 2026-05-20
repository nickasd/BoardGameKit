import BoardGameKitHost
import SceneKit
import SpriteKit
import GameKit
#if os(macOS)
import AppKit
#else
import ARKit
#endif
import AVFAudio

#if os(macOS)
public typealias ViewController = NSViewController
typealias TapGestureRecognizer = NSClickGestureRecognizer
typealias LongPressGestureRecognizer = NSPressGestureRecognizer
typealias PanGestureRecognizer = NSPanGestureRecognizer
typealias MagnificationGestureRecognizer = NSMagnificationGestureRecognizer
#else
public typealias ViewController = UIViewController
typealias TapGestureRecognizer = UITapGestureRecognizer
typealias LongPressGestureRecognizer = UILongPressGestureRecognizer
typealias PanGestureRecognizer = UIPanGestureRecognizer
typealias MagnificationGestureRecognizer = UIPinchGestureRecognizer
#endif

public class GameViewController: ViewController, SCNSceneRendererDelegate, SKSceneDelegate, GKLocalPlayerListener {
    
    fileprivate enum GestureOrigin {
        case scene2D
        case scene3D
    }
    
    public static var isPhone: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }
    
    public static var shared: GameViewController!

    #if os(iOS)
    var arViewDelegate: ARViewDelegate!
    #endif

    public private(set) var scnView: SCNView?
    public private(set) var skView: SKView?
    private var tryReconnect = false
    fileprivate var gestureOrigin: GestureOrigin?
    private(set) fileprivate var floor: SCNNode?
    private var skQueue = (queue: DispatchQueue(label: "org.desairem.BoardGameKit.skQueue", qos: .userInteractive), updates: [() -> Void]())
    private var scnQueue = (queue: DispatchQueue(label: "org.desairem.BoardGameKit.scnQueue", qos: .userInteractive), updates: [() -> Void]())
    
    public init(configuration: Configuration) {
        super.init(nibName: nil, bundle: nil)
        ConfigurationShared = configuration
        HostConfiguration.shared = configuration.host
        ClientConfiguration.shared = configuration.client
        Credits.shared = configuration.credits
        GameViewController.shared = self
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    open override func loadView() {
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient)
        } catch {
            Logger.shared.error(error.localizedDescription)
        }
        #endif
        
        #if os(macOS)
        let frame = NSScreen.main!.frame
        #else
        let frame = UIScreen.main.bounds
        #endif
        switch ClientConfiguration.shared.scenes.game {
        case .scene3D:
            let view = MySCNView(frame: frame)
            scnView = view // first few frames of SceneKit animations are discarded if starting them when a scene is static (FB9874768, fixed on M1?)
            self.view = view
            
            let overlay = SKScene() // SpriteKit app shows stretched scene until resizing window (FB14800486), SCNView.overlaySKScene disappears while resizing window (FB14817181)
            overlay.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            overlay.addChild(Scene2D.current)
            overlay.delegate = self
            
            let scene = SCNScene()
            scene.background.contents = createSceneBackground()
            scene.rootNode.addChildNode(Scene3D.current)
            scene.rootNode.addChildNode(Scene3D.mainCamera)
            let light = SCNNode()
            light.light = SCNLight()
            light.light!.type = .ambient
            scene.rootNode.addChildNode(light)
            let tempLight = SCNNode()
            tempLight.light = SCNLight()
            tempLight.light!.type = .spot
            tempLight.light!.intensity = 0
            scene.rootNode.addChildNode(tempLight)
            floor = createFloor()
            scene.rootNode.addChildNode(floor!)
            
            view.antialiasingMode = .multisampling4X
            view.autoenablesDefaultLighting = false // adding light to SceneKit scene suddenly changes how transparent objects are rendered (FB9462179)
            view.overlaySKScene = overlay
            view.scene = scene
            view.delegate = self
            #if os(macOS)
            view.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: view))
            #else
            arViewDelegate = ARViewDelegate(scnView: view)
            #endif
        case .scene2D:
            let view = SKView(frame: frame)
            skView = view
            self.view = view
            
            let scene = SKScene()
            scene.delegate = self
            scene.addChild(Scene2D.current)
            scene.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            
            view.presentScene(scene)
        }
        addGestureRecognizers()
        #if os(macOS)
//        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidChangeOcclusionState), name: NSApplication.didChangeOcclusionStateNotification, object: NSApp)
        #else
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        #endif
    }
    
    #if os(macOS)
    @objc func applicationDidChangeOcclusionState(_ notification: Notification) {
        if Scene2D.current is GameOverlayScene {
            if NSApp.occlusionState.contains(.visible) {
                ServerShared.connect()
            } else {
                ServerShared.disconnect()
            }
        }
    }
    
    open override func viewDidLayout() {
        didResize()
    }
    #else
    @objc func applicationDidEnterBackground(_ notification: Notification) {
        if (ServerShared as? WebsocketServer)?.connectionStatus == .connected {
            tryReconnect = true
            ServerShared.disconnect()
        }
    }

    @objc func applicationWillEnterForeground(_ notification: Notification) {
        if tryReconnect {
            tryReconnect = false
            ServerShared.connect()
        }
    }
    
    open override func viewDidLayoutSubviews() {
        didResize()
    }

    open override var prefersStatusBarHidden: Bool {
        return true
    }
    
    open override var shouldAutorotate: Bool {
        return true
    }
    #endif
    
    func createSceneBackground() -> Any {
        let sky = MDLSkyCubeTexture(name: "sky", channelEncoding: .float16, textureDimensions: vector_int2(x: 64, y: 64), turbidity: 1, sunElevation: 0.778, upperAtmosphereScattering: 1, groundAlbedo: 0.33)
        sky.groundColor = CGColor(gray: 0.22, alpha: 1)
        sky.gamma = 0.05
        sky.brightness = -0.44
        sky.saturation = -2
        sky.update()
        return sky
    }
    
    private func createFloor() -> SCNNode {
        let floor = SCNFloor()
        floor.reflectivity = 0.001 // setting it to 0 inundates the console with logs
        floor.reflectionFalloffEnd = 0.001
        floor.firstMaterial!.diffuse.contents = Color(red: 0.24, green: 0.47, blue: 0.67, alpha: 1)
        floor.firstMaterial!.diffuse.wrapS = .repeat
        floor.firstMaterial!.diffuse.wrapT = .repeat
        floor.firstMaterial!.transparency = 0.3
        let node = SCNNode(geometry: floor)
        node.categoryBitMask = 1 << 1
        return node
    }
    
    func updateFloor() {
        if let floor = floor, let floorImagePath = ClientConfiguration.shared.floorImagePath {
            let texture = PreparedResources.texture(named: floorImagePath)
            floor.geometry!.firstMaterial!.diffuse.contents = floorImagePath // using SKTexture instead of floorImagePath doesn't wrap
            let scale = ClientConfiguration.shared.floorImageScale
            floor.geometry!.firstMaterial!.diffuse.contentsTransform = SCNMatrix4MakeScale(SCNFloat(1000.0 * texture.size().width / texture.size().height / scale), SCNFloat(1000.0 / scale), 0)
        }
    }
    
    private func didResize() {
        if scnView != nil {
            Scene3D.current.layout()
        }
        Scene2D.current.viewSize = view.frame.size
        Scene2D.current.layout()
        ClientConfiguration.shared.scenes.mainMenu.layout()
    }
    
    public func updateSpriteKit(_ block: @escaping () -> Void) {
        skQueue.queue.async { [self] in
            skQueue.updates.append(block)
        }
    }
    
    public func update(_ currentTime: TimeInterval, for scene: SKScene) {
        skQueue.queue.sync {
            for block in skQueue.updates {
                block()
            }
            skQueue.updates.removeAll()
        }
    }
    
    public func updateSceneKit(_ block: @escaping () -> Void) {
        scnQueue.queue.async { [self] in
            scnQueue.updates.append(block)
        }
    }
    
    public func renderer(_ renderer: any SCNSceneRenderer, didApplyAnimationsAtTime time: TimeInterval) {
        scnQueue.queue.sync {
            for block in scnQueue.updates {
                block()
            }
            scnQueue.updates.removeAll()
            (Scene2D.current as? GameOverlayScene)?.layoutDynamicOverlay()
        }
    }
    
    public func showError(_ error: any Error) {
        Logger.shared.error(error.localizedDescription)
        #if os(macOS)
        GameViewController.shared.presentError(error)
        #else
        let alert = UIAlertController(title: nil, message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("button.ok", bundle: .boardGameKit, value: "OK", comment: ""), style: .cancel, handler: { _ in
            alert.dismiss(animated: true)
        }))
        GameViewController.shared.present(alert, animated: true)
        #endif
    }
    
    // MARK: - Game Center
    
    func registerGameCenter() {
        GKLocalPlayer.local.register(self)
        GKLocalPlayer.local.authenticateHandler = { viewController, error in
            if let viewController = viewController {
                #if os(macOS)
                GameViewController.shared.presentAsSheet(viewController)
                #else
                GameViewController.shared.present(viewController, animated: true)
                #endif
            } else if let error = error {
                Logger.shared.error(error.localizedDescription)
            } else {
                Logger.shared.info("Connected to GameCenter")
            }
        }
    }
    
    public func player(_ player: GKPlayer, didAccept invite: GKInvite) {
        Task { @MainActor in
            Logger.shared.info("Player \(player.displayName) did accept invite")
            if !(Scene3D.current is MainScene) {
                Scene3D.current.transition(to: MainScene())
            }
            Scene2D.current.transition(to: PlayScene())
            (Scene2D.current as! PlayScene).startGameCenter()
            (Scene2D.current as! GameCenterMatchmakerScene).player(player, didAccept: invite)
        }
    }
    
    // MARK: - Gestures
    
    fileprivate func addGestureRecognizers() {
        view.addGestureRecognizer(TapGestureRecognizer(target: self, action: #selector(tap(_:))))
        view.addGestureRecognizer(LongPressGestureRecognizer(target: self, action: #selector(longPress(_:))))
        view.addGestureRecognizer(PanGestureRecognizer(target: self, action: #selector(pan(_:))))
        view.addGestureRecognizer(MagnificationGestureRecognizer(target: self, action: #selector(pinch(_:))))
    }

    @objc func tap(_ gestureRecognizer: TapGestureRecognizer) {
        switch gestureRecognizer.state {
        case .ended:
            let point = gestureRecognizer.location(in: gestureRecognizer.view!)
            if let result = Scene2D.current.hitTest(at: point) {
                Scene2D.current.tap(result)
            } else {
                Scene3D.current.tap(at: point)
            }
        default:
            break
        }
    }
    
    @objc func longPress(_ gestureRecognizer: LongPressGestureRecognizer) {
        switch gestureRecognizer.state {
        case .began:
            Scene3D.current.longPressStart(at: gestureRecognizer.location(in: gestureRecognizer.view))
        case .ended:
            Scene3D.current.longPressEnd()
        default:
            break
        }
    }
    
    @objc func pan(_ gestureRecognizer: PanGestureRecognizer) {
        switch gestureRecognizer.state {
        case .began:
            let point = gestureRecognizer.location(in: gestureRecognizer.view)
            if let result = Scene2D.current.hitTest(at: point) {
                Scene2D.current.panStart(result)
                gestureOrigin = .scene2D
            } else {
                Scene3D.current.panStart(at: point)
                gestureOrigin = .scene3D
            }
        case .changed:
            var translation = gestureRecognizer.translation(in: gestureRecognizer.view)
            #if os(iOS)
            translation.y = -translation.y
            #endif
            let point = gestureRecognizer.location(in: gestureRecognizer.view)
            switch gestureOrigin! {
            case .scene2D:
                Scene2D.current.panUpdate(at: point, translation: translation)
            case .scene3D:
                Scene3D.current.panUpdate(at: point, translation: translation)
            }
        case .ended:
            var translation = gestureRecognizer.translation(in: gestureRecognizer.view)
            var velocity = gestureRecognizer.velocity(in: gestureRecognizer.view)
            #if os(iOS)
            translation = -1 * translation
            velocity = -0.01 * velocity
            #endif
            switch gestureOrigin! {
            case .scene2D:
                Scene2D.current.panEnd(translation: translation, velocity: velocity)
            case .scene3D:
                Scene3D.current.panEnd(translation: translation, velocity: velocity)
            }
            gestureOrigin = nil
        default:
            break
        }
    }

    @objc func pinch(_ gestureRecognizer: MagnificationGestureRecognizer) {
        let point = gestureRecognizer.location(in: gestureRecognizer.view)
        #if os(macOS)
        let scale = gestureRecognizer.magnification
        #else
        let scale = gestureRecognizer.scale
        #endif
        switch gestureRecognizer.state {
        case .began:
            if let result = Scene2D.current.hitTest(at: point) {
                Scene2D.current.pinchStart(result, scale: scale)
                gestureOrigin = .scene2D
            } else {
                Scene3D.current.pinchStart(at: point, scale: scale)
                gestureOrigin = .scene3D
            }
        case .changed:
            switch gestureOrigin! {
            case .scene2D:
                Scene2D.current.pinchUpdate(scale: scale)
            case .scene3D:
                Scene3D.current.pinchUpdate(scale: scale)
            }
        case .ended:
            switch gestureOrigin! {
            case .scene2D:
                Scene2D.current.pinchEnd(scale: scale)
            case .scene3D:
                Scene3D.current.pinchEnd(scale: scale)
            }
            gestureOrigin = nil
        default:
            break
        }
    }
    
}

class MySCNView: SCNView {
    
    #if os(macOS)
    override func mouseMoved(with event: NSEvent) {
        Scene3D.current.mouseMoved(with: event)
    }
    
    private var scrollStart = CGPoint.zero
    
    override func scrollWheel(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if event.phase == .began || event.momentumPhase == .began {
            scrollStart = point
            if let result = Scene2D.current.hitTest(at: point) {
                Scene2D.current.scrollStart(result)
                GameViewController.shared.gestureOrigin = .scene2D
            } else {
                Scene3D.current.scrollStart(at: point)
                GameViewController.shared.gestureOrigin = .scene3D
            }
        } else if event.phase == .changed || event.momentumPhase == .changed {
            let velocity = CGPoint(x: event.scrollingDeltaX, y: event.scrollingDeltaY)
            scrollStart = scrollStart + velocity
            let translation = point - scrollStart
            switch GameViewController.shared.gestureOrigin! {
            case .scene2D:
                Scene2D.current.scrollUpdate(translation: translation)
            case .scene3D:
                Scene3D.current.scrollUpdate(translation: translation)
            }
        } else if event.phase == .ended || event.momentumPhase == .ended {
            let velocity = CGPoint(x: event.scrollingDeltaX, y: event.scrollingDeltaY)
            scrollStart = scrollStart + velocity
            let translation = point - scrollStart
            switch GameViewController.shared.gestureOrigin! {
            case .scene2D:
                Scene2D.current.scrollEnd(translation: translation, velocity: velocity)
            case .scene3D:
                Scene3D.current.scrollEnd(translation: translation, velocity: velocity)
            }
            GameViewController.shared.gestureOrigin = nil
        }
    }
    #endif

}

#if os(iOS)
@MainActor class ARViewDelegate: NSObject {
    
    private let scnView: SCNView
    
    init(scnView: SCNView) {
        self.scnView = scnView
    }
    
    var isARMode: Bool {
        return GameViewController.shared.view is ARSCNView
    }
    
    func toggleARMode() {
        switch GameViewController.shared.view {
        case let view as ARSCNView:
            view.session.pause()
            let background = GameViewController.shared.createSceneBackground()
            scnView.scene = view.scene
            scnView.scene!.rootNode.addChildNode(GameViewController.shared.floor!)
            scnView.scene!.background.contents = background
            scnView.scene!.lightingEnvironment.contents = background
            scnView.overlaySKScene = view.overlaySKScene
            GameViewController.shared.view = scnView
        case let view as SCNView:
            let arView = ARSCNView()
            arView.autoenablesDefaultLighting = false
            let configuration = ARWorldTrackingConfiguration()
            configuration.planeDetection = .horizontal
            arView.session.run(configuration)
            GameViewController.shared.floor!.removeFromParentNode()
            arView.scene = view.scene!
            arView.overlaySKScene = view.overlaySKScene
            GameViewController.shared.view = arView
            GameViewController.shared.addGestureRecognizers()
        default:
            preconditionFailure()
        }
    }
    
}
#endif
