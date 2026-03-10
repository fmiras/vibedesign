import Foundation

struct UploadService {
    private static let baseURL = "https://www.fmiras.com/api/spacedesign"

    static func getPresignedURL(filename: String, mimeType: String = "image/jpeg") async throws -> PresignedResponse {
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "filename", value: filename),
            URLQueryItem(name: "type", value: mimeType),
        ]
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw UploadError.presignFailed
        }
        return try JSONDecoder().decode(PresignedResponse.self, from: data)
    }

    static func uploadImage(data imageData: Data, to signedUrl: String) async throws {
        var request = URLRequest(url: URL(string: signedUrl)!)
        request.httpMethod = "PUT"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await URLSession.shared.upload(for: request, from: imageData)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw UploadError.uploadFailed
        }
    }

    static func uploadPhoto(_ imageData: Data, filename: String) async throws -> String {
        let presigned = try await getPresignedURL(filename: filename)
        try await uploadImage(data: imageData, to: presigned.signedUrl)
        return presigned.publicUrl
    }
}

enum UploadError: LocalizedError {
    case presignFailed
    case uploadFailed

    var errorDescription: String? {
        switch self {
        case .presignFailed: "Failed to get upload URL"
        case .uploadFailed: "Failed to upload image"
        }
    }
}
