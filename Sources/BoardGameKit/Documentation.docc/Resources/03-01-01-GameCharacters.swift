import BoardGameKit
import BoardGameKitHost

struct CrazyEightsConfiguration: Configuration {
    let host = HostConfiguration(gameCharacters: CrazyEightsCharacter.self, game: CrazyEightsGame.self)
    let client = ClientConfiguration(scenes: .init(game: .scene3D(CrazyEightsGameScene.self)))
    let credits = Credits(developer: "I")
}

enum CrazyEightsCharacter: String, GameCharacter {
    case ShowWhite
    case Pinocchio
    case Dumbo
    case Bambi
    case Cinderella
    case Alice
    case PeterPan
    case Aurora
    case Arielle
    case Belle
    case Aladdin
    case Simba
    case Pocahontas
    case Hercules
    case Mulan
    case Tarzan
}
