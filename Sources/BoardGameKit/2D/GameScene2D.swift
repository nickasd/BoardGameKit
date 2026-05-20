import BoardGameKitHost
import SceneKit
import SpriteKit
import AVFoundation

@MainActor public protocol GameScene2D: SKNode {
    associatedtype PlayerNode: GamePlayerNode2D
    associatedtype Options: GameOptions
    
    var players: [PlayerNode] { get }
    /// If the local player is the only player on the current device, this property is set only once, otherwise it is alternatively set and unset when switching between the device's local players.
    var localPlayer: PlayerNode? { get set }
    /// The event handler receives actions from the game scene and is responsible for acting appropriately, e.g. by forwarding game actions to the server.
    var actionHandler: GameSceneActionHandler2D? { get set }
    
    func load(localizedPlayers: [LocalizedPlayer], options: Options) async throws
    func handle(eventGroup: GameManager.EventGroupResponse) throws
    func handle(error: GameManager.GameErrorResponse) throws
    /// Called when a game is closed. Implement this method to release any cyclic references and avoid memory leaks.
    func close()
    /// The overlay can contain buttons and other elements. When the game is disabled, such as when navigating the timeline, the overlay is hidden.
    var overlay: SKNode? { get }
    /// This method is called when the size of the overlay changes.
    func layoutOverlay(in frame: CGRect)
    
    /**
     This method is called when the private data for the given `player` should be hidden or shown.
     
     At the beginning of a live game, this method is called for each player with `hide` equal to `true`. A usual implementation sets `hideChildren = hide` for all `NodeGroup` objects that contain private data.

     If the local player is the only player on the current device, this method is called with `hide` equal to `false` for the local player. If there are two or more players sharing the current device and the current player changes, this method is called with `hide` equal to `true` with the current local player, followed by a call with `hide` equal to `false` with the new local player.
     */
    func hidePrivateData(_ hide: Bool, for player: PlayerNode)
    
    /**
     This method is called when the actions for the given `player` should be enabled or disabled.
     
     Before the player state changes, this method is called with `enable` equal to `false`, and after the state has changed, this method is called with `enable` equal to `true`.
     
     In a usual implementation, you set the `isEnabled` property of all interactive `ButtonNode` objects to be equal to `enable`. At the same time you also set the `tap` and `drag` properties.
     */
    func enableActions(_ enable: Bool, for player: PlayerNode)
}

@MainActor public protocol GamePlayerNode2D: SKNode, Identifiable where ID == UUID {
    var id: ID { get }
    var overlay: PlayerOverlay? { get }
}

@MainActor public protocol GameSceneActionHandler2D {
    func sendAction(_ data: any GameAction)
}

extension GameScene2D {
    
    public func load(localizedPlayers: [LocalizedPlayer], options: String?) async throws {
        try await load(localizedPlayers: localizedPlayers, options: options.map({ try RequestCoder.decode(Options.self, from: Data($0.utf8)) }) ?? Options())
    }
    
    public var overlay: SKNode? {
        return nil
    }
    
    public func layoutOverlay(in frame: CGRect) {
        positionPlayerOverlays(for: players, in: frame)
    }
    
    public func positionPlayerOverlays(for players: [PlayerNode], in frame: CGRect) {
        for (i, player) in players.enumerated() {
            player.overlay?.position = CGPoint(x: frame.minX + 30, y: frame.maxY - 30 - Double(i) * 30)
        }
    }
    
}

extension GamePlayerNode2D {
    
    public var overlay: PlayerOverlay? {
        return nil
    }
    
}
