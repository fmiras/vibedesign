import SwiftUI

struct ProcessingView: View {
    @Bindable var item: SpaceItem
    @Environment(\.dismiss) private var dismiss
    @State private var generationTask: Task<Void, Never>?
    @State private var error: String?
    @State private var navigateToDetail = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                if let error {
                    errorContent(error)
                } else {
                    loadingContent
                }
            }
            .padding()
            .navigationTitle("Generating 3D Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        generationTask?.cancel()
                        if item.status == "generating" {
                            item.status = "failed"
                        }
                        dismiss()
                    }
                }
            }
            .navigationDestination(isPresented: $navigateToDetail) {
                ModelDetailView(item: item)
            }
            .task {
                await generate()
            }
        }
    }

    private var loadingContent: some View {
        VStack(spacing: 24) {
            Spacer()

            AsyncImage(url: URL(string: item.imageUrl)) { image in
                image
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } placeholder: {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.quaternary)
                    .frame(height: 200)
                    .overlay {
                        ProgressView()
                    }
            }

            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)

                Text("Creating your 3D model...")
                    .font(.headline)

                Text("This may take up to 2 minutes")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private func errorContent(_ message: String) -> some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.yellow)

            Text("Generation Failed")
                .font(.title2.bold())

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Retry") {
                error = nil
                Task { await generate() }
            }
            .buttonStyle(.glassProminent)

            Spacer()
        }
    }

    private func generate() async {
        guard item.status == "generating", !item.imageUrl.isEmpty else { return }

        let task = Task {
            do {
                let prediction = try await GenerationService.generate3DModel(from: item.imageUrl)
                guard !Task.isCancelled else { return }

                if let output = prediction.output {
                    item.modelFileUrl = output.model_file
                    item.colorVideoUrl = output.color_video
                    item.status = "ready"
                    navigateToDetail = true
                } else {
                    item.status = "failed"
                    error = "No output in response"
                }
            } catch is CancellationError {
                // cancelled by user
            } catch {
                guard !Task.isCancelled else { return }
                item.status = "failed"
                self.error = error.localizedDescription
            }
        }
        generationTask = task
        await task.value
    }
}
