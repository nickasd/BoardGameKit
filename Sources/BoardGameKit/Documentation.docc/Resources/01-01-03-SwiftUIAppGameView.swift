import SwiftUI
import BoardGameKit

@main
struct CrazyEightsApp: App {
    var body: some Scene {
        WindowGroup {
            GameView(configuration: CrazyEightsConfiguration())
        }
    }
}
