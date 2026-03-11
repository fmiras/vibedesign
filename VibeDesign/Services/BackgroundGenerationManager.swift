import Foundation
import SwiftData

/// Manages background upload → generation → GLB download for SpaceItems.
/// Runs tasks in parallel — each item gets its own Task.
@MainActor
@Observable
final class BackgroundGenerationManager {
    private var activeTasks: [UUID: Task<Void, Never>] = [:]

    /// Start processing an item in the background.
    /// Call after creating the SpaceItem and saving its local image.
    func process(_ item: SpaceItem) {
        let itemID = item.id
        guard activeTasks[itemID] == nil else { return }

        let task = Task {
            await self.run(item)
            self.activeTasks.removeValue(forKey: itemID)
        }
        activeTasks[itemID] = task
    }

    /// Resume any items that were left in uploading/generating state (e.g. after app restart).
    func resumeIncomplete(_ items: [SpaceItem]) {
        for item in items where item.status == "uploading" || item.status == "generating" {
            process(item)
        }
    }

    func cancel(_ itemID: UUID) {
        activeTasks[itemID]?.cancel()
        activeTasks.removeValue(forKey: itemID)
    }

    // MARK: - Pipeline

    private func run(_ item: SpaceItem) async {
        // Step 1: Upload image if needed
        if item.status == "uploading" {
            guard let localURL = item.localImageURL,
                  let imageData = try? Data(contentsOf: localURL)
            else {
                item.status = "failed"
                return
            }

            do {
                let publicUrl = try await UploadService.uploadPhoto(imageData, filename: item.name)
                guard !Task.isCancelled else { return }
                item.imageUrl = publicUrl
                item.status = "generating"
            } catch {
                guard !Task.isCancelled else { return }
                item.status = "failed"
                print("[BG] Upload failed for \(item.id): \(error)")
                return
            }
        }

        // Step 2: Generate 3D model
        if item.status == "generating" {
            do {
                let prediction = try await GenerationService.generate3DModel(from: item.imageUrl)
                guard !Task.isCancelled else { return }

                if let output = prediction.output {
                    item.modelFileUrl = output.model_file
                    item.colorVideoUrl = output.color_video
                    item.status = "ready"

                    // Step 3: Download GLB immediately (before Replicate URL expires)
                    if let modelFile = output.model_file {
                        await downloadGLB(item: item, from: modelFile)
                    }
                } else {
                    item.status = "failed"
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                item.status = "failed"
                print("[BG] Generation failed for \(item.id): \(error)")
            }
        }
    }

    private func downloadGLB(item: SpaceItem, from urlString: String) async {
        guard let url = URL(string: urlString) else { return }

        do {
            let (tempURL, _) = try await URLSession.shared.download(from: url)
            let filename = "\(item.id.uuidString).glb"
            let dest = SpaceItem.modelsDirectory.appendingPathComponent(filename)

            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tempURL, to: dest)

            item.localModelPath = filename
            print("[BG] GLB saved for \(item.id)")
        } catch {
            print("[BG] GLB download failed for \(item.id): \(error)")
        }
    }
}
