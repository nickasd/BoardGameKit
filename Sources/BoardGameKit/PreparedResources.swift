import BoardGameKitHost
import SceneKit
import SpriteKit
import AVFoundation
import CoreServices

@MainActor public class PreparedResources {
    
    public struct Resources: Sendable {
        let paths: [String]
        let options: Options
        
        public init(paths: [String], options: Options) {
            self.paths = paths
            self.options = options
        }
    }
    
    public struct Options: OptionSet, Sendable {
        public let rawValue: Int
        
        public static let loadMaterials = Options(rawValue: 1 << 0)
        public static let loadTextures = Options(rawValue: 1 << 1)
        
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
    }
    
    private static var materials = [String: SCNMaterial]()
    private static var textures = [String: SKTexture]()
    private static var sounds = [String: AVAudioPlayer]()
    private static var scenes = [String: SCNNode]()
    
    public static func load(_ resources: [Resources]) async throws {
        let start = Date()
        for resources in resources {
            for path in resources.paths {
                let resourceUrl = Bundle.main.resourceURL!.appendingPathComponent(path)
                if (try? resourceUrl.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true {
                    try await load(url: resourceUrl, options: resources.options)
                } else {
                    let enumerator = FileManager.default.enumerator(at: resourceUrl, includingPropertiesForKeys: [.isDirectoryKey, .typeIdentifierKey], options: [.skipsHiddenFiles])!
                    while let url = enumerator.nextObject() as? URL {
                        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == false else {
                            continue
                        }
                        try await load(url: url, options: resources.options)
                    }
                }
            }
        }
        Logger.shared.debug("Loaded resources in \(-start.timeIntervalSinceNow)")
    }
    
    private static func load(url: URL, options: Options) async throws {
        let name = (url.path as NSString).substring(from: (Bundle.main.resourceURL!.path as NSString).length + 1)
        guard let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
            throw HostError(message: "Error loading resource at '\(url.path)'.")
        }
        if contentType.conforms(to: .image) == true {
            if options.contains(.loadMaterials) && materials[name] == nil {
                let material = SCNMaterial()
                material.diffuse.contents = url
                Logger.shared.debug("Prepared material \(name)")
                materials[name] = material
            }
            if options.contains(.loadTextures) && textures[name] == nil {
                guard let data = try? Data(contentsOf: url) else {
                    fatalError("Error loading image at '\(url.path)'")
                }
                #if os(macOS)
                let image = NSImage(data: data)!.representations.last!.cgImage(forProposedRect: nil, context: nil, hints: nil)! // SKTexture(image:) uses the first (smallest) NSImage representation and ends up having a different size than on iOS
                #else
                let image = UIImage(data: data)!.cgImage!
                #endif
                let texture = SKTexture(cgImage: image) // SceneKit object rendered with simple image vs SKTexture is different (FB8979522)
                await texture.preload()
                Logger.shared.debug("Prepared texture \(name)")
                textures[name] = texture
            }
        } else if contentType.conforms(to: .audio) == true {
            if sounds[name] == nil {
                guard let sound = try? AVAudioPlayer(contentsOf: url) else {
                    fatalError("Error loading sound named '\(name)'.")
                }
                sound.prepareToPlay()
                Logger.shared.debug("Prepared sound \(name)")
                sounds[name] = sound
            }
        } else if ["dae", "scn"].contains(url.pathExtension) {
            if scenes[name] == nil {
                guard let scene = SCNScene(named: name)?.rootNode else {
                    fatalError("Error loading scene named '\(name)'.")
                }
                Logger.shared.debug("Prepared scene \(name)")
                scenes[name] = scene
            }
        } else {
            throw HostError(message: "Unknown resource type at '\(url.path)'.")
        }
    }
    
    public static func material(named name: String) -> SCNMaterial {
        guard let material = materials[name] else {
            preconditionFailure("No material named '\(name)' has been prepared.")
        }
        return material.copy() as! SCNMaterial
    }
    
    public static func texture(named name: String) -> SKTexture {
        guard let texture = textures[name] else {
            preconditionFailure("No texture named '\(name)' has been prepared.")
        }
        return texture.copy() as! SKTexture
    }
    
    public static func sound(named name: String) -> AVAudioPlayer {
        guard let sound = sounds[name] else {
            preconditionFailure("No sound named '\(name)' has been prepared.")
        }
        return sound
    }
    
    public static func scene(named name: String) -> SCNNode {
        guard let scene = scenes[name] else {
            preconditionFailure("No scene named '\(name)' has been prepared.")
        }
        return scene
    }
    
}
