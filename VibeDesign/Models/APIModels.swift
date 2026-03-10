import Foundation

struct PresignedResponse: Codable {
    let signedUrl: String
    let publicUrl: String
}

struct PredictionRequest: Codable {
    let image_url: String
}

struct PredictionResponse: Codable {
    let id: String
    let status: String
    let output: PredictionOutput?
}

struct PredictionOutput: Codable {
    let model_file: String?
    let color_video: String?
    let normal_video: String?
    let combined_video: String?
    let gaussian_ply: String?
    let no_background_images: [String]?
}
