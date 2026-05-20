import BoardGameKit
import BoardGameKitHost

struct CrazyEightsConfiguration: Configuration {
    let host = HostConfiguration(game: CrazyEightsGame.self)
}
