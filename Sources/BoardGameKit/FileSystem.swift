#if os(macOS)
import AppKit
import UniformTypeIdentifiers

@MainActor public class FileSystem {
    
    public static let shared = FileSystem()
    
    public func askForOpenUrl(ofType type: String, block: @escaping (_ url: URL?) -> Void) {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [UTType(filenameExtension: type)!]
        if openPanel.runModal() == .cancel {
            block(nil)
        } else {
            block(openPanel.urls[0])
        }
    }
    
    public func save(_ data: Data, fileName: String) throws {
        let savePanel = NSSavePanel()
        if let type = UTType(filenameExtension: (fileName as NSString).pathExtension) {
            savePanel.allowedContentTypes = [type]
        }
        savePanel.nameFieldStringValue = fileName
        if savePanel.runModal() == .cancel {
            return
        }
        let url = savePanel.url!
        try data.write(to: url)
    }
    
}
#else
import UIKit
import UniformTypeIdentifiers

public class FileSystem: NSObject, UIDocumentPickerDelegate {
    
    public static let shared = FileSystem()
    
    private var block: ((_ url: URL?) -> Void)?
    
    public func askForOpenUrl(ofType type: String, block: @escaping (_ url: URL?) -> Void) {
        self.block = block
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType(filenameExtension: type)!])
        documentPicker.delegate = self
        GameViewController.shared.present(documentPicker, animated: true)
    }

    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let url = urls[0]
        if url.startAccessingSecurityScopedResource() {
            block?(url)
        } else {
            block?(nil)
        }
        block = nil
    }
    
    public func save(_ data: Data, fileName: String) throws {
        let viewController = UIActivityViewController(activityItems: [FileProvider(data: data, filename: fileName)], applicationActivities: nil)
        viewController.modalPresentationStyle = .popover
        viewController.popoverPresentationController?.sourceView = GameViewController.shared.view
        viewController.popoverPresentationController?.sourceRect = .zero
        GameViewController.shared.present(viewController, animated: true)
    }
    
    class FileProvider: UIActivityItemProvider {
        
        let data: Data
        let filename: String
        
        init(data: Data, filename: String) {
            self.data = data
            self.filename = filename
            super.init(placeholderItem: data)
        }
        
        override var item: Any {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try? data.write(to: url)
            return url
        }
        
    }
    
}
#endif
