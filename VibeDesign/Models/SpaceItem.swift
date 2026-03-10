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

    init(name: String, imageUrl: String) {
        self.id = UUID()
        self.name = name
        self.imageUrl = imageUrl
        self.status = "uploading"
        self.createdAt = Date()
    }
}
