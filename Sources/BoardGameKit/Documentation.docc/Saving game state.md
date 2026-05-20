# Saving game state

BoardGameKit makes it easy to save the game state. If you already implemented your game logic, there's very little that you need to change, if anything.

## Overview

BoardGameKit saves every input to the game, from the first ambient action, to all player actions happening afterwards. When loading a save file, it feeds all saved actions to a new game as if they were happening in real time. This way, the game incrementally restores the old state and implicitly validates all actions at the same time; if the game logic became incompatible or the save file was corrupted, loading the save file would throw an error.

On the other hand, if at any time you notice that there's a flaw in the game logic, you can correct it and reload old games; if the saved actions are still valid, a game will be restored with the new logic, and if it is not, you can manually remove from the save file all actions starting from the one that caused the error and resume playing from there. As opposed to saving a snapshot of the current game state and restoring a game from that, you'll always know whether that state is reachable by a valid sequence of actions.

While this approach creates a bigger save file than storing a snapshot of the current game state, it is less error-prone, doesn't require any extra work, and has one practical side effect: it allows to see the entire game history at any time, both during and after the game.

## Actions

Ambient actions are defined inside the `Game` implementation and usually contain no data:

```swift
struct StartGameAction: GameAction {
    static let name = "startGame"
}
```

Player actions are defined the same way, but often contain some data:

```swift
struct PlayCardAction: GameAction {
    static let name = "playCard"
    
    let card: String
}
```

Whenever BoardGameKit receives such an action, either from the client via `GameSceneActionHandler.sendAction(_:)` or from the game itself via `GameActionContext.queue(player:action:)`, it is appended to `SavedGame.actions`. Since `Request` implements `Codable`, the whole `SavedGame` can be stored as a JSON file which you can inspect and modify.

## Randomness

In order to restore a game to its old state, you need to record any random value generated during a live game and use them again during a following replay. You can do so by implementing the `ReplayableGameAction` protocol which requires that you define a `ReplayData` type that conforms to `Codable`, then by adding an additional argument to your action handler: an `inout` argument of your request's `ReplayData` type.

```swift
struct StartRoundAction: ReplayableGameAction {
    static let name = "startRound"
    
    struct ReplayData: Codable {
        let cards: [UUID: [String]]
    }
    
    var replayData: [ReplayData]?
}

private func startGame(data: StartRoundAction, replay: inout StartRoundAction.ReplayData?, context: GameActionContext) throws {
    for player in players {
        let cards = try cardDeck.draw(count: playerCardCount, ids: replay?.cards.get(for: player.id))
        player.handCards.append(contentsOf: cards)
    }
    replay = .init(cards: Dictionary(uniqueKeysWithValues: players.map({ ($0.id, $0.handCards.ids) })))
    ...
}
```

During a live game, `replay` is `nil`, but during a replay it is set to the value that was previously recorded. Some helper methods (like `RangeReplaceableCollection.draw(count:ids)` in the example above) accept an optional `id` or `ids` argument that allows them to return a deterministic value; if that argument is `nil`, they return a random value instead.

Whether `replay` is `nil` or not, you need to write to it before the action handler returns. The data that you write will be provided again the next time the game is loaded.
