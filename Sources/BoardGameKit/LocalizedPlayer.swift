import Foundation
import BoardGameKitHost

public struct LocalizedPlayer: Identifiable {
    public let name: String
    public let gameCharacter: (any GameCharacter)?
    public let savedPlayer: SavedPlayer
    
    public init(name: String, gameCharacter: (any GameCharacter)?, savedPlayer: SavedPlayer) {
        self.name = name
        self.gameCharacter = gameCharacter
        self.savedPlayer = savedPlayer
    }
    
    public init(savedPlayer: SavedPlayer, savedPlayers: [SavedPlayer]) {
        let name = savedPlayer.name ?? savedPlayer.id.uuidString
        let extendedName = switch savedPlayer.type {
        case .real(let userName):
            if savedPlayer.id == User.local?.id {
                String(format: NSLocalizedString("playerName.i", bundle: .boardGameKit, value: "%@ (I)", comment: ""), name)
            } else if !userName.isEmpty {
                String(format: "%1$@ (%2$@)", name, userName)
            } else {
                name
            }
        case .bot(let strategy):
            if HostConfiguration.shared.botStrategies.count == 1 {
                String(format: NSLocalizedString("playerName.bot.single", bundle: .boardGameKit, value: "%@ (bot)", comment: ""), name)
            } else {
                String(format: NSLocalizedString("playerName.bot.variant", bundle: .boardGameKit, value: "%1$@ (%2$@ bot)", comment: ""), name, (try? HostConfiguration.shared.gameStrategy?.from(strategy) as? LocalizedLabel)?.localizedLabel ?? strategy)
            }
        case .deviceClient(let host):
            if let host = savedPlayer.host.flatMap({ savedPlayers.first(id: $0) }) {
                String(format: "%1$@ (%2$@)", name, host.name ?? host.id.uuidString)
            } else {
                preconditionFailure("Invalid player host \(host).")
            }
        }
        self.init(name: extendedName, gameCharacter: savedPlayer.name.flatMap({ ConfigurationShared.gameCharacter(for: $0) }), savedPlayer: savedPlayer)
    }
    
    public var id: UUID {
        return savedPlayer.id
    }
}

public protocol LocalizedLabel {
    var localizedLabel: String { get }
}
