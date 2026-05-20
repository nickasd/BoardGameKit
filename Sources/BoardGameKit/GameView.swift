import SwiftUI

#if os(macOS)
public struct GameView: View {
    public let configuration: any Configuration
    
    public init(configuration: any Configuration) {
        self.configuration = configuration
    }
    
    public var body: some View {
        if #available(macOS 14.0, *) {
            SwiftUI_GameViewController(configuration: configuration)
                .frame(idealWidth: .infinity, idealHeight: .infinity)
                .onAppear {
                    NSWindow.allowsAutomaticWindowTabbing = false
                }
                .onKeyPress { keyPress in
                    (Scene2D.current as? GameOverlayScene)?.onKeyPress(keyPress) ?? .ignored
                }
        } else {
            SwiftUI_GameViewController(configuration: configuration)
                .frame(idealWidth: .infinity, idealHeight: .infinity)
                .onAppear {
                    NSWindow.allowsAutomaticWindowTabbing = false
                }
        }
    }
}

struct SwiftUI_GameViewController: NSViewControllerRepresentable {
    let configuration: any Configuration
    
    init(configuration: any Configuration) {
        self.configuration = configuration
    }
    
    func makeNSViewController(context: Context) -> some NSViewController {
        return GameViewController(configuration: configuration)
    }
        
    func updateNSViewController(_ nsViewController: NSViewControllerType, context: Context) {
    }
}
#else
public struct GameView: View {
    public let configuration: any Configuration
    
    public init(configuration: any Configuration) {
        self.configuration = configuration
    }
    
    public var body: some View {
        if #available(iOS 17.0, *) {
            SwiftUI_GameViewController(configuration: configuration)
                .ignoresSafeArea()
                .persistentSystemOverlays(.hidden)
                .onKeyPress { keyPress in
                    (Scene2D.current as? GameOverlayScene)?.onKeyPress(keyPress) ?? .ignored
                }
        } else if #available(iOS 16.0, *) {
            SwiftUI_GameViewController(configuration: configuration)
                .ignoresSafeArea()
                .persistentSystemOverlays(.hidden)
        } else {
            SwiftUI_GameViewController(configuration: configuration)
                .ignoresSafeArea()
        }
    }
}

struct SwiftUI_GameViewController: UIViewControllerRepresentable {
    let configuration: any Configuration
    
    init(configuration: any Configuration) {
        self.configuration = configuration
    }
    
    func makeUIViewController(context: Context) -> some UIViewController {
        return GameViewController(configuration: configuration)
    }
    
    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) {
    }
}
#endif

extension Bundle {
    
    public static var boardGameKit: Bundle {
        return Bundle(for: GameViewController.self)
    }
    
}
