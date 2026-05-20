import BoardGameKit
import BoardGameKitHost

struct CrazyEightsConfiguration: Configuration {
    let host = HostConfiguration(game: CrazyEightsGame.self)
    let client = ClientConfiguration(scenes: .init(game: .scene3D(CrazyEightsGameScene.self)))
}
