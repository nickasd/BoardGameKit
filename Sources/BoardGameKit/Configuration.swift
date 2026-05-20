import BoardGameKitHost
import SpriteKit

nonisolated(unsafe) public var ConfigurationShared: Configuration!

public protocol Configuration {
    var host: HostConfiguration { get }
    var client: ClientConfiguration { get }
    var credits: Credits { get }
    
    func gameCharacter(for rawValue: String) -> (any GameCharacter)?
}

public struct ClientConfiguration {
    public struct Scenes {
        public enum GameSceneType {
            case scene3D(any GameScene3D.Type)
            case scene2D(any GameScene2D.Type)
        }
        
        public let mainMenu: MainMenuScene.Type
        public let game: GameSceneType
        public let options: (any GameOptionsView.Type)?
        public let rules: SKNode.Type?
        
        public init(mainMenu: MainMenuScene.Type = MainMenuScene.self, game: GameSceneType, options: (any GameOptionsView.Type)? = nil, rules: SKNode.Type? = nil) {
            self.mainMenu = mainMenu
            self.game = game
            self.options = options
            self.rules = rules
        }
    }
    
    public static var shared: ClientConfiguration!
    
    public let prepareResources: [PreparedResources.Resources]
    public let scenes: Scenes
    public let playerIconsPath: String?
    public let floorImagePath: String?
    public let floorImageScale: Double
    public let sampleGamesPath: String?
    public let sampleGameScale: Float
    public let theme: Theme
    
    public init(prepareResources: [PreparedResources.Resources] = [], scenes: Scenes, playerIconsPath: String? = nil, floorImagePath: String? = nil, floorImageScale: Double = 1.0, sampleGamesPath: String? = nil, sampleGameScale: Float = 1.0, theme: Theme = Theme()) {
        self.prepareResources = prepareResources
        self.scenes = scenes
        self.playerIconsPath = playerIconsPath
        self.floorImagePath = floorImagePath
        self.floorImageScale = floorImageScale
        self.sampleGamesPath = sampleGamesPath
        self.sampleGameScale = sampleGameScale
        self.theme = theme
    }
}

public struct Theme {
    public let launchScreenBackgroundColor: Color?
    public let launchScreenBackgroundImagePath: String?
    public let defaultScreenBackgroundImagePath: String?
    public let titleFontName: String?
    public let titleFontSize: Double
    public let titleImagePath: String?
    public let labelFontName: String
    public let labelBaseFontSize: Double
    public let textButtonBackgroundPaths: [String]
    public let textButtonPadding: CGSize?
    public let textButtonTapSoundPath: String?
    public let disabledButtonTapSoundPath: String?
    public let imageButtonBackgroundPath: String?
    public let imageButtonAlternateBackgroundPath: String?
    public let imageButtonTapSoundPath: String?
    public let backButtonBackgroundPath: String?
    public let creditsFontName: String?
    public let creditsFontSize: Double
    public let creditsTextColor: Color?
    public let creditsTextShadowColor: Color?
    
    public init(launchScreenBackgroundColor: Color? = nil, launchScreenBackgroundImagePath: String? = nil, defaultScreenBackgroundImagePath: String? = nil, titleImagePath: String? = nil, titleFontName: String? = nil, titleFontSize: Double = 200.0, labelFontName: String = "HelveticaNeue-Light", labelBaseFontSize: Double = 30.0, textButtonBackgroundPaths: [String] = [], textButtonPadding: CGSize? = nil, textButtonTapSoundPath: String? = nil, disabledButtonTapSoundPath: String? = nil, imageButtonBackgroundPath: String? = nil, imageButtonAlternateBackgroundPath: String? = nil, imageButtonTapSoundPath: String? = nil, backButtonBackgroundPath: String? = nil, creditsFontName: String? = nil, creditsFontSize: Double = 20.0, creditsTextColor: Color? = nil, creditsTextShadowColor: Color? = nil) {
        self.launchScreenBackgroundColor = launchScreenBackgroundColor
        self.launchScreenBackgroundImagePath = launchScreenBackgroundImagePath
        self.defaultScreenBackgroundImagePath = defaultScreenBackgroundImagePath
        self.titleImagePath = titleImagePath
        self.titleFontName = titleFontName
        self.titleFontSize = titleFontSize
        self.labelFontName = labelFontName
        self.labelBaseFontSize = labelBaseFontSize
        self.textButtonBackgroundPaths = textButtonBackgroundPaths
        self.textButtonPadding = textButtonPadding
        self.textButtonTapSoundPath = textButtonTapSoundPath
        self.disabledButtonTapSoundPath = disabledButtonTapSoundPath
        self.imageButtonBackgroundPath = imageButtonBackgroundPath
        self.imageButtonAlternateBackgroundPath = imageButtonAlternateBackgroundPath
        self.imageButtonTapSoundPath = imageButtonTapSoundPath
        self.backButtonBackgroundPath = backButtonBackgroundPath
        self.creditsFontName = creditsFontName
        self.creditsFontSize = creditsFontSize
        self.creditsTextColor = creditsTextColor
        self.creditsTextShadowColor = creditsTextShadowColor
    }
    
    public func labelFontSize(for fontSize: Double) -> Double {
        return fontSize / 30.0 * labelBaseFontSize
    }
    
    public func labelFont(size: Double) -> Font {
        return Font(name: labelFontName, size: labelFontSize(for: size))!
    }
}

public struct Credits {
    public static var shared: Credits!
    
    public static func mailtoUrl(recipient: String) -> URL {
        var urlComponents = URLComponents(string: "mailto:\(recipient)")!
        urlComponents.queryItems = [URLQueryItem(name: "subject", value: "\(Bundle.main.name) Feedback"), URLQueryItem(name: "body", value: "\n\n\n \(Bundle.main.name) \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String) (\(Bundle.main.version))\n\(ProcessInfo.processInfo.operatingSystemName) \(ProcessInfo.processInfo.operatingSystemVersionShortString)")]
        return urlComponents.url!
    }
    
    public let author: String?
    public let design: String?
    public let publisher: String?
    public let developer: String?
    public let websiteUrl: URL?
    public let websiteLabel: String?
    public let feedbackUrl: URL?
    
    public init(author: String? = nil, design: String? = nil, publisher: String? = nil, developer: String? = nil, websiteUrl: URL? = nil, websiteLabel: String? = nil, feedbackUrl: URL? = nil) {
        self.author = author
        self.design = design
        self.publisher = publisher
        self.developer = developer
        self.websiteUrl = websiteUrl
        self.websiteLabel = websiteLabel
        self.feedbackUrl = feedbackUrl
    }
    
    var authorWithLabel: String? {
        return author.map({ String(format: NSLocalizedString("credits.author", bundle: .boardGameKit, value: "A game by\n%@", comment: ""), $0) })
    }
    
    var designWithLabel: String? {
        return design.map({ String(format: NSLocalizedString("credits.design", bundle: .boardGameKit, value: "Illustrated by\n%@", comment: ""), $0) })
    }
    
    var publisherWithLabel: String? {
        return publisher.map({ String(format: NSLocalizedString("credits.publisher", bundle: .boardGameKit, value: "Published by\n%@", comment: ""), $0) })
    }
    
    var developerWithLabel: String? {
        return developer.map({ String(format: NSLocalizedString("credits.developer", bundle: .boardGameKit, value: "Digital adaptation by\n%@", comment: ""), $0) })
    }
}

extension Configuration {
    
    public func gameCharacter(for rawValue: String) -> (any GameCharacter)? {
        return host.gameCharacters?.init(rawValue: rawValue)
    }
    
}
