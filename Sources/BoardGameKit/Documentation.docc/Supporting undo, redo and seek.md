# Supporting undo, redo and seek

BoardGameKit makes various types available that allow your game to support undo, redo and seek operations. Undo and redo are instantaneous operations visualized in BoardGameKit as short animations from one state to another, while seek operations allow the player to jump to any point in the timeline and navigate it at different speeds.

## Overview

Support for undo and redo is provided by the `UndoManager` and `Timeline` classes. `UndoManager` records instantaneous operations, like adding or removing an element from an array, while `Timeline` records animations and is used exclusively on the client.

An undo or redo operation can be triggered by opening the menu during a game and hitting the respective arrow buttons. When hitting the pause button, the game is paused and the timeline controls appear: to perform a seek operation, hit any point on the timeline, or drag the timeline knob, or hit the unwind or rewind buttons, once or multiple times to increase the speed.

## Undo manager

On both the host and the client, you get access to the undo manager via `GameContext.current.undoManager`. A game request context is made available during game initialization and whenever a game action is being handled.

Often though it's not necessary to access the undo manager directly. BoardGameKit provides some types that register undo and redo operations automatically.

In general, it's sufficient to add the `@Recorded` annotation to any property that can change during the game. This property wrapper simply registers an undo operation that resets its previous value, hence it's compatible with all value types such as `Bool`, `Int`, `Double`, `Array` and `Dictionary`.

```swift
@Recorded private var playedCards = [Card]()
```

Some specialized classes are available which handle changes more efficiently for arrays (`RecordedArray`) and dictionaries (`RecordedDictionary`). Instead of recording the entire current value, they only record the actual change.

```swift
private var playedCards = RecordedArray<Card>()
```

If you need more granular control, you may add undo operations directly via `GameContext.current.undoManager.addEvent(_:)`.

## Timeline

On the client, you get access to the timeline via `GameSceneContext.current.timeline`. Similarly to the game context, a game scene context is made available during game scene initialization and whenever a game action is being handled.

Often it's not necessary to access the timeline directly. BoardGameKit provides some types that register timeline animations automatically.

The `NodeGroup` class is at the top of the hierarchy of classes that allow you to create node groups in different dispositions.
- `CardNodeFan`: holds an array of `CardNode` objectes, usually to represent cards held by a player hand.
- `NodeDeck` and `CardNodeDeck`: an array of nodes stacked on top of each other and facing downwards, their primary side hidden from the players.
- `NodeArray` and `CardNodeArray`: an array of nodes, one beside the other.
- `NodeDiscardPile` and `CardNodeDiscardPile`:  and array of nodes stacked on top of each other and facing upwards, their primary side visible to the players.
- `FixedNodeGroup` and `FixedCardNodeGroup`: a group of nodes with custom transforms.
- `NodeGrid`
- `NodeCircle`

When a game element is moved from a location to another, you first use one of the following methods:
- `appendNewNode(_:)`
- `appendNewNodes(_:)`
- `insertNewNode(_:at:)`
- `insertNewNodes(_:atOffsets:)`

These methods register an undo operation with the `UndoManager`. Then you animate the changes by calling `animateNodes(timeOffset:duration:)`. This method registers a timeline animation for each moved node via the `MoveAnimation` class.

If you need more granular control, you may create an instance of `MoveAnimation` or `TimelineAnimation` and add it to the timeline by calling `GameSceneContext.current.timeline.addAnimation(_:)`.
