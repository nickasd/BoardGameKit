# Hiding private data

BoardGameKit offers methods to sent certain information only to the players who are allowed to see it.

## Overview

In many games, players hold private information, such as hand cards hidden from the other players. Before a game has ended, that information should only be known by the respetive player and the host. (While the host would technically be able to know the information by inspecting the save file, that information is not visualized in the game scene.) After a game ends, the whole game history is sent to each player and stored as a file that can be loaded up in the Archive menu. An archived game is read-only and displays all information, even that that was previously private.

## Host

The recommended way to mark certain data in a response as private is by implementing the `PrivateEvent` protocol. This protocol requires that you add a subtype `PrivateData` that implements `Codable`.

```swift
struct StartGameEvent: PrivateGameEvent {
    static let name = "startGame"
    
    struct PrivateData: Codable {
        let cards: [String]
    }
    
    let cardCount: Int
}
```

Instead of calling `GameActionContext.sendToAllPlayers(_:)`, you send private data by calling `GameActionContext.sendToAllPlayers(_:privateData:)`. The first argument is still the response type, and the second argument is a `PrivatePlayerData` type that allows you to specify which players need to receive which private data. When sending the response, BoardGameKit encodes the necessary private data separately for each player.

The following examples assume that the `GamePlayer` implementation has a `handCards` property which is an array of card objects that conform to `Identifiable`. The `ids` property is a BoardGameKit extension that returns an array of each element's `id`.

- Private data for one player:

```swift
context.sendToAllPlayers(StartRoundEvent(cardCount: playerCardCount),
    privateData: .init(.init(cards: players[0].handCards.ids), for: players[0]))
```

- Same private data for some players:

```swift
context.sendToAllPlayers(StartRoundEvent(cardCount: playerCardCount),
    privateData: .init(.init(cards: players[0].handCards.ids), for: [players[0]]))
```

- Different private data for some players:

```swift
context.sendToAllPlayers(StartRoundEvent(cardCount: playerCardCount),
    privateData: .init([players[0]: .init(cards: players[0].handCards.ids)]))
```

- Different private data for each player:

```swift
context.sendToAllPlayers(StartRoundEvent(cardCount: playerCardCount),
    privateData: .init({ .init(cards: $0.handCards.ids) }, for: players))
```

## Client

To accept private data, the client declares the event handler with an additional `privateData` argument of type `PrivateDataList?` and checks whether a certain player has private data by calling its `get(for:)` method, passing the player's ID as the first argument. Usually this is done in a `for` loop that iterates over all players, since the client cannot know which players have private data and which don't (or whether it's an archived game with all private data revealed to all players).

```swift
private func startRound(data: CrazyEightsGame.StartRoundEvent, privateData: CrazyEightsGame.StartRoundEvent.PrivateDataList?) {
    table.cardDeck.initialize(count: Card.allCards.count)
    for (i, player) in players.enumerated() {
        if let data = privateData?.get(for: player.id) {
            player.handCards.appendNewNodes(table.cardDeck.lastChildNodes(withNames: data.cards))
        } else {
            player.handCards.appendNewNodes(table.cardDeck.lastChildNodes(hiddenCount: data.cardCount))
        }
        player.handCards.animateNodes(timeOffset: TimeInterval(i) / TimeInterval(players.count))
    }
}
```

For those players that get the private data, `NodeGroup` and all its subclasses offer the following methods to get the relevant child nodes:

- firstChildNode(withName:)
- firstChildNodes(withNames:)
- lastChildNode(withName:)
- lastChildNodes(withNames:)

Note that these methods are designed to work even when the node group is hiding its children from the current player. For instance, when a player on a different device (and whose cards are hidden from the local player) plays a card, that card would be revealed at the beginning of the animation; any of these methods would try to find the card or cards with the given names, and if they cannot be found, it would pick the first (or last) cards and assign them the new names. The forward animation would then unhide the cards as soon as they begin moving from the player's hand to their new position, and the backward animation would hide them again as soon as they are back on the player's hand.

For those players that don't get to see the private data, it's usually necessary for the host to send some other information, like the number of cards being dealt. The client then calls one of the following `NodeGroup` methods to get one or more child nodes which show no information (for example, cards would show a blank front side):

- firstChildNodeHidden()
- firstChildNodesHidden(count:)
- lastChildNodeHidden()
- lastChildNodes(hiddenCount:)
