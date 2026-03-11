import GLTFKit2
import SceneKit
import SwiftData
import SwiftUI

struct GalleryView: View {
    @Query(sort: \SpaceItem.createdAt, order: .reverse) private var items: [SpaceItem]
    @Binding var showCapture: Bool
    @AppStorage("rotateGallery") private var rotateGallery = true
    @AppStorage("useImagePreview") private var useImagePreview = false
    @Environment(BackgroundGenerationManager.self) private var generationManager

    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 250), spacing: 12),
    ]

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView(
                        "No Captures Yet",
                        systemImage: "cube.transparent",
                        description: Text("Tap + to create your first 3D model.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(items) { item in
                                NavigationLink(value: item) {
                                    GalleryCell(
                                        item: item,
                                        rotate: rotateGallery,
                                        useImagePreview: useImagePreview
                                    )
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .navigationTitle("Gallery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCapture = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .navigationDestination(for: SpaceItem.self) { item in
                ModelDetailView(item: item)
            }
            .onAppear {
                // Resume any incomplete items on launch
                let incomplete = items.filter { $0.status == "uploading" || $0.status == "generating" }
                generationManager.resumeIncomplete(incomplete)
            }
        }
    }
}

struct GalleryCell: View {
    let item: SpaceItem
    var rotate: Bool
    var useImagePreview: Bool

    private let cellHeight: CGFloat = 220

    var body: some View {
        Group {
            if item.status == "ready" && !useImagePreview {
                SpinningThumbnailView(item: item, rotate: rotate)
            } else {
                localOrRemoteImage
                    .clipped()
            }
        }
        .frame(height: cellHeight)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .topTrailing) {
            statusBadge
                .padding(8)
        }
    }

    @ViewBuilder
    private var localOrRemoteImage: some View {
        if let localURL = item.localImageURL,
           FileManager.default.fileExists(atPath: localURL.path),
           let uiImage = UIImage(contentsOfFile: localURL.path)
        {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
        } else if !item.imageUrl.isEmpty {
            AsyncImage(url: URL(string: item.imageUrl)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    placeholder(systemName: "exclamationmark.triangle")
                default:
                    placeholder(systemName: "photo")
                        .overlay { ProgressView() }
                }
            }
        } else {
            placeholder(systemName: "photo")
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch item.status {
        case "uploading":
            ProgressView()
                .padding(6)
                .background(.ultraThinMaterial, in: .circle)
        case "generating":
            ProgressView()
                .padding(6)
                .background(.ultraThinMaterial, in: .circle)
        case "failed":
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .padding(6)
                .background(.ultraThinMaterial, in: .circle)
        default:
            EmptyView()
        }
    }

    private func placeholder(systemName: String) -> some View {
        Rectangle()
            .fill(.quaternary)
            .overlay {
                Image(systemName: systemName)
                    .font(.title)
                    .foregroundStyle(.secondary)
            }
    }
}

/// Lightweight spinning 3D thumbnail using SceneKit.
/// The spin is applied to a wrapper node so the camera stays fixed.
struct SpinningThumbnailView: UIViewRepresentable {
    let item: SpaceItem
    var rotate: Bool

    func makeUIView(context: Context) -> SCNView {
        let sceneView = SCNView()
        sceneView.backgroundColor = .secondarySystemBackground
        sceneView.preferredFramesPerSecond = 30
        sceneView.antialiasingMode = .multisampling2X
        sceneView.isUserInteractionEnabled = false
        // Must be true from the start so actions play once the scene loads
        sceneView.rendersContinuously = true
        sceneView.isPlaying = true
        sceneView.loops = true

        context.coordinator.rotate = rotate
        loadModel(into: sceneView, coordinator: context.coordinator)

        return sceneView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.rotate = rotate
        guard let spinNode = context.coordinator.spinNode else { return }

        if rotate {
            if spinNode.action(forKey: "spin") == nil {
                let spin = SCNAction.repeatForever(
                    SCNAction.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 12)
                )
                spinNode.runAction(spin, forKey: "spin")
            }
            uiView.isPlaying = true
        } else {
            spinNode.removeAction(forKey: "spin")
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var rotate = true
        var spinNode: SCNNode?
    }

    private func loadModel(into sceneView: SCNView, coordinator: Coordinator) {
        // Prefer local persisted GLB, fall back to cached or remote
        let fileURL: URL? = {
            if let localURL = item.localModelURL,
               FileManager.default.fileExists(atPath: localURL.path) {
                return localURL
            }
            let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            let cached = cacheDir.appendingPathComponent("\(item.id.uuidString).glb")
            if FileManager.default.fileExists(atPath: cached.path) {
                return cached
            }
            return nil
        }()

        if let fileURL {
            setupScene(from: fileURL, into: sceneView, coordinator: coordinator)
        } else if let urlString = item.modelFileUrl, let url = URL(string: urlString) {
            Task {
                do {
                    let (tempURL, _) = try await URLSession.shared.download(from: url)
                    let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                    let glbPath = cacheDir.appendingPathComponent("\(item.id.uuidString).glb")
                    try? FileManager.default.removeItem(at: glbPath)
                    try FileManager.default.moveItem(at: tempURL, to: glbPath)
                    setupScene(from: glbPath, into: sceneView, coordinator: coordinator)
                } catch {
                    print("Thumbnail download failed: \(error)")
                }
            }
        }
    }

    private func setupScene(from fileURL: URL, into sceneView: SCNView, coordinator: Coordinator) {
        GLTFAsset.load(with: fileURL, options: [:]) { _, status, maybeAsset, _, _ in
            guard status == .complete, let asset = maybeAsset else { return }
            let source = GLTFSCNSceneSource(asset: asset)
            guard let loadedScene = source.defaultScene else { return }
            DispatchQueue.main.async {
                let scene = SCNScene()

                // Lighting
                let ambient = SCNLight()
                ambient.type = .ambient
                ambient.intensity = 500
                let ambientNode = SCNNode()
                ambientNode.light = ambient
                scene.rootNode.addChildNode(ambientNode)

                let directional = SCNLight()
                directional.type = .directional
                directional.intensity = 600
                let dirNode = SCNNode()
                dirNode.light = directional
                dirNode.eulerAngles = SCNVector3(-Float.pi / 4, Float.pi / 4, 0)
                scene.rootNode.addChildNode(dirNode)

                // Wrap model content in a spin node (so camera doesn't spin)
                let spinWrapper = SCNNode()
                for child in loadedScene.rootNode.childNodes {
                    spinWrapper.addChildNode(child.clone())
                }
                scene.rootNode.addChildNode(spinWrapper)
                coordinator.spinNode = spinWrapper

                // Frame camera on the spin wrapper
                let (minVec, maxVec) = spinWrapper.boundingBox
                let center = SCNVector3(
                    (minVec.x + maxVec.x) / 2,
                    (minVec.y + maxVec.y) / 2,
                    (minVec.z + maxVec.z) / 2
                )
                let extent = max(maxVec.x - minVec.x, maxVec.y - minVec.y, maxVec.z - minVec.z)

                let camera = SCNCamera()
                camera.automaticallyAdjustsZRange = true
                let cameraNode = SCNNode()
                cameraNode.camera = camera
                cameraNode.position = SCNVector3(center.x, center.y, center.z + extent * 1.8)
                cameraNode.look(at: center)
                scene.rootNode.addChildNode(cameraNode)

                sceneView.scene = scene
                sceneView.pointOfView = cameraNode

                // Start spin
                if coordinator.rotate {
                    let spin = SCNAction.repeatForever(
                        SCNAction.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 12)
                    )
                    spinWrapper.runAction(spin, forKey: "spin")
                }
            }
        }
    }
}
