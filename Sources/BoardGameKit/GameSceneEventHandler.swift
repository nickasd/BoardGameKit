import Foundation
import BoardGameKitHost

@MainActor public class GameSceneEventHandler<PlayerNode: Identifiable, PlayerState: GameState> where PlayerNode.ID == UUID {
    
    private var eventHandles = [String: (PlayerEvent) throws -> Void]()
    private var errorHandles = [String: (String) throws -> Void]()
    private var playerStateChangeHandles = [PlayerState: (PlayerNode.ID, [PlayerState], [PlayerState]) -> Void]()
    private var playerStates = [PlayerNode.ID: [PlayerState]]()
    
    public init() {
    }
    
    public func register<T: GameEvent>(_ handle: @escaping (_ data: T) throws -> Void) {
        register(T.name) { event in
            let data = try RequestCoder.decode(T.self, from: Data(event.data.utf8))
            try handle(data)
        }
    }
    
    public func register<T: PrivateGameEvent>(_ handle: @escaping (_ data: T, _ privateData: T.PrivateDataList?) throws -> Void) {
        register(T.name) { event in
            let data = try RequestCoder.decode(T.self, from: Data(event.data.utf8))
            let privateData = try event.privateData.map({ try RequestCoder.decode(T.PrivateDataList.self, from: Data($0.utf8)) })
            try handle(data, privateData)
        }
    }
    
    /// Registers a failable event. The event and the corresponding action must have the same name.
    public func register<T: FailableGameEvent>(_ handle: @escaping (_ data: FailableGameEventResult<T>) throws -> Void) {
        register(T.name) { event in
            let data = try RequestCoder.decode(T.self, from: Data(event.data.utf8))
            try handle(.success(data))
        }
        registerError(T.name) { error in
            let data = try RequestCoder.decode(T.Failure.self, from: Data(error.utf8))
            try handle(.failure(data))
        }
    }
    
    /// Registers a failable private event. The event and the corresponding action must have the same name.
    public func register<T: FailableGameEvent & PrivateGameEvent>(_ handle: @escaping (_ data: FailablePrivateGameEventResult<T>) throws -> Void) {
        register(T.name) { event in
            let data = try RequestCoder.decode(T.self, from: Data(event.data.utf8))
            let privateData = try event.privateData.map({ try RequestCoder.decode(T.PrivateDataList.self, from: Data($0.utf8)) })
            try handle(.success((data, privateData)))
        }
        registerError(T.name) { error in
            let data = try RequestCoder.decode(T.Failure.self, from: Data(error.utf8))
            try handle(.failure(data))
        }
    }
    
    private func register(_ name: String, _ handle: @escaping (_ event: PlayerEvent) throws -> Void) {
        if eventHandles.updateValue({ data in
            try handle(data)
        }, forKey: name) != nil {
            preconditionFailure("Event \(name) is already registered.")
        }
    }
    
    private func registerError(_ name: String, _ handle: @escaping (_ error: String) throws -> Void) {
        if errorHandles.updateValue({ data in
            try handle(data)
        }, forKey: name) != nil {
            preconditionFailure("Error \(name) is already registered.")
        }
    }
    
    public func handle(eventGroup: GameManager.EventGroupResponse) throws {
        if let playerStateChanges = eventGroup.playerStateChanges {
            for state in playerStateChanges {
                setState(try PlayerState.from(state.state), for: state.id)
            }
        }
        for event in eventGroup.events {
            if let handle = eventHandles[event.name] {
                try handle(event)
            } else {
                throw HostError(message: "Event \(event) is not registered.")
            }
        }
    }
    
    private func setState(_ state: [PlayerState], for player: PlayerNode.ID) {
        let oldState = playerStates.updateValue(state, forKey: player) ?? []
        GameContext.current.undoManager?.addEvent(UndoManager.Event(id: "GameSceneEventHandler.setState", block: { [self] in
            setState(oldState, for: player)
        }))
        for singleState in oldState + state {
            if let handle = playerStateChangeHandles[singleState] {
                handle(player, oldState, state)
            }
        }
    }
    
    public func handle(error: GameManager.GameErrorResponse) throws {
        if let handle = errorHandles[error.action] {
            try handle(error.error)
        } else {
            throw HostError(message: "Error \(error.action) is not registered.")
        }
    }
    
    public func registerChange(_ handle: @escaping (_ player: PlayerNode.ID, _ oldState: [PlayerState], _ newState: [PlayerState]) -> Void, for state: PlayerState...) {
        for state in state {
            if playerStateChangeHandles.updateValue(handle, forKey: state) != nil {
                preconditionFailure("Change for \(state) is already registered.")
            }
        }
    }
    
    public func state(for player: PlayerNode) -> [PlayerState] {
        return playerStates[player.id] ?? []
    }
    
}

public typealias FailableGameEventResult<T: FailableGameEvent> = Result<T, T.Failure>
public typealias FailablePrivateGameEventResult<T: FailableGameEvent & PrivateGameEvent> = Result<(data: T, privateData: T.PrivateDataList?), T.Failure>
