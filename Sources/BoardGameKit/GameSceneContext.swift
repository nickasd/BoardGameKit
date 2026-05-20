import BoardGameKitHost
import SceneKit
import SpriteKit
import AVFAudio

@MainActor public class GameSceneContext {
    
    private enum Keys {
        static let gameSceneContext = "gameSceneContext"
    }
    
    public static var current: GameSceneContext {
        guard let current = Thread.current.threadDictionary[Keys.gameSceneContext] as? GameSceneContext else {
            preconditionFailure("There is no current GameSceneContext set.")
        }
        return current
    }
    
    public let gameContext: GameContext
    public let timeline = Timeline()
    public let isPhone: Bool
    public let hostPlayer: UUID?
    
    public init(gameContext: GameContext, isPhone: Bool = false, hostPlayer: UUID? = nil) {
        self.gameContext = gameContext
        self.isPhone = isPhone
        self.hostPlayer = hostPlayer
    }
    
    public func makeCurrent<T>(_ block: () throws -> T) rethrows -> T {
        if Thread.current.threadDictionary[Keys.gameSceneContext] as? GameSceneContext != nil {
            preconditionFailure("A current GameSceneContext is already set.")
        }
        Thread.current.threadDictionary[Keys.gameSceneContext] = self
        defer {
            Thread.current.threadDictionary[Keys.gameSceneContext] = nil
        }
        return try gameContext.makeCurrent {
            return try block()
        }
    }
    
}

@MainActor public protocol GameSceneDataStructure {
}

extension GameSceneDataStructure {
    
    public func addUndoEvent(id: String, _ block: @escaping (Self) -> Void) {
        GameContext.current.undoManager?.addEvent(UndoManager.Event(id: id, block: { block(self) }))
    }
    
    public func addAnimation(_ animation: TimelineAnimation) {
        GameSceneContext.current.timeline.addAnimation(animation)
    }
    
    public func addTimeOffset(_ time: TimeInterval) {
        GameSceneContext.current.timeline.addTimeOffset(time)
    }
    
    public func playSound(_ sound: AVAudioPlayer, timeOffset: TimeInterval = 0) {
        let timeline = GameSceneContext.current.timeline
        timeline.addEphemeralAnimation(TimelineAnimation(id: "GameSceneDataStructure.playSound", subject: sound, startTime: timeline.currentTime + timeline.timeOffset + timeOffset, duration: sound.duration, enter: { _ in
            sound.play()
        }, progress: { _ in }))
    }

}

extension SCNNode: GameSceneDataStructure {
}

extension SKNode: GameSceneDataStructure {
}
