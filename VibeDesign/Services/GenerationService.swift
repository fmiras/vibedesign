import Foundation

struct GenerationService {
    private static let baseURL = "https://www.fmiras.com/api/spacedesign/prediction"

    /// Set to `true` during development to use mocked responses (no Replicate credits burned).
    static var testMode = true

    /// Creates a prediction and polls until it completes.
    static func generate3DModel(from publicUrl: String) async throws -> PredictionResponse {
        let predictionId = try await createPrediction(imageUrl: publicUrl)
        return try await pollUntilComplete(id: predictionId)
    }

    // MARK: - Create Prediction

    private static func createPrediction(imageUrl: String) async throws -> String {
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if testMode {
            request.setValue("true", forHTTPHeaderField: "X-Test-Mode")
        }
        request.timeoutInterval = 30

        let body = PredictionRequest(image_url: imageUrl)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse

        guard let http, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            throw GenerationError.serverError("POST failed (\(http?.statusCode ?? 0)): \(body)")
        }

        let prediction = try JSONDecoder().decode(PredictionResponse.self, from: data)
        return prediction.id
    }

    // MARK: - Poll Status

    private static func pollUntilComplete(id: String) async throws -> PredictionResponse {
        let pollURL = URL(string: "\(baseURL)/\(id)")!

        for _ in 0..<90 { // max ~3 minutes at 2s intervals
            try Task.checkCancellation()
            try await Task.sleep(for: .seconds(2))

            var request = URLRequest(url: pollURL)
            if testMode {
                request.setValue("true", forHTTPHeaderField: "X-Test-Mode")
            }
            request.timeoutInterval = 15

            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse

            guard let http, (200...299).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "no body"
                throw GenerationError.serverError("GET failed (\(http?.statusCode ?? 0)): \(body)")
            }

            let prediction = try JSONDecoder().decode(PredictionResponse.self, from: data)

            switch prediction.status {
            case "succeeded":
                return prediction
            case "failed", "canceled":
                throw GenerationError.serverError("Prediction \(prediction.status)")
            default:
                // "starting" or "processing" — keep polling
                continue
            }
        }

        throw GenerationError.timeout
    }
}

enum GenerationError: LocalizedError {
    case serverError(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .serverError(let detail): "Server error: \(detail)"
        case .timeout: "Generation timed out after 3 minutes"
        }
    }
}
