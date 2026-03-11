import Foundation
import SwiftData

@Model
class SpaceItem {
    var id: UUID
    var name: String
    var imageUrl: String
    var modelFileUrl: String?
    var colorVideoUrl: String?
    var status: String
    var createdAt: Date
    /// Relative path under Documents/images/ for the source JPEG.
    var localImagePath: String?
    /// Relative path under Documents/models/ for the persisted GLB.
    var localModelPath: String?

    init(name: String, imageUrl: String) {
        self.id = UUID()
        self.name = name
        self.imageUrl = imageUrl
        self.status = "uploading"
        self.createdAt = Date()
    }

    // MARK: - Local file helpers

    static var imagesDirectory: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var modelsDirectory: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    var localImageURL: URL? {
        guard let localImagePath else { return nil }
        return Self.imagesDirectory.appendingPathComponent(localImagePath)
    }

    var localModelURL: URL? {
        guard let localModelPath else { return nil }
        return Self.modelsDirectory.appendingPathComponent(localModelPath)
    }
}
