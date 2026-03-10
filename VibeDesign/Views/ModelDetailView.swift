import GLTFKit2
import SceneKit
import SwiftData
import SwiftUI

struct ModelDetailView: View {
    @Bindable var item: SpaceItem
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var showDeleteConfirmation = false
    @State private var localModelURL: URL?
    @State private var isLoadingModel = false
    @State private var loadError: String?

    var body: some View {
        ZStack {
            if let localModelURL {
                SceneKitGLBView(url: localModelURL)
                    .ignoresSafeArea()
            } else if isLoadingModel {
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Loading 3D model...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if let loadError {
                ContentUnavailableView(
                    "Could not load model",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
            } else {
                VStack(spacing: 16) {
                    AsyncImage(url: URL(string: item.imageUrl)) { image in
                        image
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    } placeholder: {
                        ProgressView()
                    }
                    .frame(maxHeight: 400)

                    statusView
                }
                .padding()
            }
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let modelFileUrl = item.modelFileUrl, let url = URL(string: modelFileUrl) {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }

            ToolbarSpacer(.fixed)

            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .confirmationDialog("Delete this item?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                modelContext.delete(item)
                dismiss()
            }
        }
        .task {
            await downloadModelIfNeeded()
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch item.status {
        case "uploading":
            Label("Uploading...", systemImage: "arrow.up.circle")
                .foregroundStyle(.secondary)
        case "generating":
            Label("Generating 3D model...", systemImage: "hourglass")
                .foregroundStyle(.secondary)
        case "failed":
            Label("Generation failed", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)

            Button("Retry") {
                Task { await retryGeneration() }
            }
            .buttonStyle(.glassProminent)
        default:
            EmptyView()
        }
    }

    private func downloadModelIfNeeded() async {
        guard item.status == "ready",
              let urlString = item.modelFileUrl,
              let url = URL(string: urlString),
              localModelURL == nil
        else { return }

        isLoadingModel = true
        defer { isLoadingModel = false }

        do {
            let (tempURL, _) = try await URLSession.shared.download(from: url)
            let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            let glbPath = cacheDir.appendingPathComponent("\(item.id.uuidString).glb")

            try? FileManager.default.removeItem(at: glbPath)
            try FileManager.default.moveItem(at: tempURL, to: glbPath)

            localModelURL = glbPath
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func retryGeneration() async {
        guard !item.imageUrl.isEmpty else { return }
        item.status = "generating"
        loadError = nil

        do {
            let prediction = try await GenerationService.generate3DModel(from: item.imageUrl)
            if let output = prediction.output {
                item.modelFileUrl = output.model_file
                item.colorVideoUrl = output.color_video
                item.status = "ready"
                await downloadModelIfNeeded()
            } else {
                item.status = "failed"
            }
        } catch {
            item.status = "failed"
        }
    }
}

enum ModelLoadError: LocalizedError {
    case cannotParse

    var errorDescription: String? {
        "Could not parse 3D model file"
    }
}

/// SceneKit-based GLB viewer using GLTFKit2 + Metal rendering.
struct SceneKitGLBView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> SCNView {
        let sceneView = SCNView()

        // Metal GPU rendering
        sceneView.preferredFramesPerSecond = 120
        sceneView.antialiasingMode = .multisampling4X
        sceneView.isJitteringEnabled = true
        sceneView.backgroundColor = .clear

        // Camera interaction
        sceneView.allowsCameraControl = true
        sceneView.defaultCameraController.interactionMode = .orbitTurntable
        sceneView.defaultCameraController.inertiaEnabled = true

        // Load GLB asynchronously via GLTFKit2
        GLTFAsset.load(with: url, options: [:]) { _, status, maybeAsset, maybeError, _ in
            DispatchQueue.main.async {
                guard status == .complete, let asset = maybeAsset else {
                    print("GLTFKit2 failed to load GLB: \(maybeError?.localizedDescription ?? "unknown")")
                    return
                }

                let source = GLTFSCNSceneSource(asset: asset)
                guard let scene = source.defaultScene else {
                    print("GLTFKit2: no default scene found")
                    return
                }

                // Studio lighting
                let keyLight = SCNLight()
                keyLight.type = .directional
                keyLight.intensity = 800
                keyLight.color = UIColor.white
                keyLight.castsShadow = true
                keyLight.shadowMode = .deferred
                keyLight.shadowSampleCount = 16
                keyLight.shadowRadius = 3
                keyLight.shadowColor = UIColor(white: 0, alpha: 0.5)
                let keyNode = SCNNode()
                keyNode.light = keyLight
                keyNode.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 4, 0)
                scene.rootNode.addChildNode(keyNode)

                let fillLight = SCNLight()
                fillLight.type = .directional
                fillLight.intensity = 300
                fillLight.color = UIColor(white: 0.9, alpha: 1)
                let fillNode = SCNNode()
                fillNode.light = fillLight
                fillNode.eulerAngles = SCNVector3(-Float.pi / 6, -Float.pi / 3, 0)
                scene.rootNode.addChildNode(fillNode)

                let ambientLight = SCNLight()
                ambientLight.type = .ambient
                ambientLight.intensity = 200
                ambientLight.color = UIColor(white: 0.95, alpha: 1)
                let ambientNode = SCNNode()
                ambientNode.light = ambientLight
                scene.rootNode.addChildNode(ambientNode)

                sceneView.scene = scene

                // HDR camera
                if let camera = sceneView.pointOfView?.camera {
                    camera.wantsHDR = true
                    camera.bloomIntensity = 0.3
                    camera.bloomThreshold = 0.8
                    camera.wantsExposureAdaptation = true
                }
            }
        }

        return sceneView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
}
