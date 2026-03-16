import ARKit
import GLTFKit2
import SceneKit
import SwiftData
import SwiftUI

struct ARPlacementView: View {
    @Query(sort: \SpaceItem.createdAt, order: .reverse) private var allItems: [SpaceItem]
    @AppStorage("arUnitCm") private var useCm = true

    private var readyItems: [SpaceItem] {
        allItems.filter { $0.status == "ready" }
    }

    @State private var selectedItem: SpaceItem?
    @State private var arCoordinator = ARCoordinatorState()

    var body: some View {
        ZStack {
            ARViewContainer(
                selectedItem: $selectedItem,
                coordinatorState: $arCoordinator
            )
            .ignoresSafeArea()

            // Top toolbar when object selected
            if arCoordinator.hasSelectedNode {
                VStack {
                    HStack {
                        Button {
                            arCoordinator.requestDeselect = true
                        } label: {
                            Image(systemName: "xmark")
                                .font(.body.weight(.semibold))
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)

                        Spacer()

                        Button(role: .destructive) {
                            arCoordinator.requestDelete = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.body)
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    Spacer()
                }
            }

            // Bottom controls
            VStack(spacing: 12) {
                Spacer()

                if arCoordinator.hasSelectedNode {
                    // "Pinch to scale" hint like Camera app
                    Text("Pinch to scale · Drag to rotate")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.4), in: Capsule())

                    dimensionsPanel
                } else {
                    instructionLabel
                }

                modelPicker
            }
            .padding(.bottom, 30)
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
    }

    // MARK: - Dimensions Panel

    private var dimensionsPanel: some View {
        let unit = useCm ? "cm" : "in"
        let factor: Float = useCm ? 100.0 : 39.3701

        let dims = arCoordinator.selectedDimensions
        let w = dims.x * factor
        let h = dims.y * factor
        let d = dims.z * factor

        return HStack(spacing: 6) {
            dimensionLabel("W", value: w, unit: unit) { newVal in
                guard w > 0 else { return }
                arCoordinator.requestScaleMultiplier = newVal / w
            }
            dimensionLabel("H", value: h, unit: unit) { newVal in
                guard h > 0 else { return }
                arCoordinator.requestScaleMultiplier = newVal / h
            }
            dimensionLabel("D", value: d, unit: unit) { newVal in
                guard d > 0 else { return }
                arCoordinator.requestScaleMultiplier = newVal / d
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private func dimensionLabel(_ label: String, value: Float, unit: String, onCommit: @escaping (Float) -> Void) -> some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            DimensionField(value: value, unit: unit, onCommit: onCommit)
        }
    }

    // MARK: - Instruction

    @ViewBuilder
    private var instructionLabel: some View {
        if readyItems.isEmpty {
            Text("Generate a 3D model first")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
        } else {
            let text = selectedItem == nil ? "Select a model below" : "Tap a surface to place"
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
        }
    }

    // MARK: - Model Picker

    private var modelPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(readyItems) { item in
                    ARModelButton(item: item, isSelected: selectedItem?.id == item.id) {
                        selectedItem = item
                    }
                }
            }
            .padding(.horizontal)
        }
        .frame(height: 72)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal)
    }
}

// MARK: - Dimension Text Field

private struct DimensionField: View {
    let value: Float
    let unit: String
    let onCommit: (Float) -> Void

    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 1) {
            TextField("", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 44)
                .font(.caption.monospacedDigit())
                .focused($focused)
                .onAppear { text = formatted(value) }
                .onChange(of: value) { _, newVal in
                    if !focused { text = formatted(newVal) }
                }
                .onSubmit { commitValue() }
                .onChange(of: focused) { _, isFocused in
                    if !isFocused { commitValue() }
                }
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func formatted(_ v: Float) -> String {
        String(format: "%.1f", v)
    }

    private func commitValue() {
        guard let newVal = Float(text), newVal > 0, newVal != value else {
            text = formatted(value)
            return
        }
        onCommit(newVal)
    }
}

// MARK: - Coordinator State

@Observable
class ARCoordinatorState {
    var hasSelectedNode = false
    var requestDelete = false
    var requestDeselect = false
    var requestScaleMultiplier: Float = 0
    var selectedDimensions = SIMD3<Float>(0, 0, 0)
}

// MARK: - AR Model Button

private struct ARModelButton: View {
    let item: SpaceItem
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AsyncImage(url: URL(string: item.imageUrl)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Rectangle().fill(.quaternary).overlay { ProgressView() }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
            )
        }
    }
}

// MARK: - AR SceneKit Container

struct ARViewContainer: UIViewRepresentable {
    @Binding var selectedItem: SpaceItem?
    @Binding var coordinatorState: ARCoordinatorState

    func makeCoordinator() -> Coordinator {
        Coordinator(state: coordinatorState)
    }

    func makeUIView(context: Context) -> ARSCNView {
        let arView = ARSCNView()
        arView.autoenablesDefaultLighting = true
        arView.automaticallyUpdatesLighting = true

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        arView.session.run(config)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tap)

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        arView.addGestureRecognizer(pinch)

        // One-finger pan to rotate selected object
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        arView.addGestureRecognizer(pan)

        context.coordinator.arView = arView
        return arView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        context.coordinator.selectedItem = selectedItem
        context.coordinator.state = coordinatorState

        if coordinatorState.requestDelete {
            context.coordinator.deleteSelectedNode()
            coordinatorState.requestDelete = false
        }
        if coordinatorState.requestDeselect {
            context.coordinator.deselectNode()
            coordinatorState.requestDeselect = false
        }
        if coordinatorState.requestScaleMultiplier != 0 {
            context.coordinator.applyScaleMultiplier(coordinatorState.requestScaleMultiplier)
            coordinatorState.requestScaleMultiplier = 0
        }
    }

    class Coordinator: NSObject {
        weak var arView: ARSCNView?
        var selectedItem: SpaceItem?
        var state: ARCoordinatorState
        private var loadedScenes: [UUID: SCNScene] = [:]
        private var selectedNode: SCNNode?
        private var boundingBoxNode: SCNNode?
        private var selectedOriginalExtent = SIMD3<Float>(0, 0, 0)
        private var initialPinchScale: Float = 1.0
        private var lastPanX: CGFloat = 0

        private static let cageColor = UIColor.systemCyan

        init(state: ARCoordinatorState) {
            self.state = state
        }

        // MARK: Gestures

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let arView else { return }
            let location = gesture.location(in: arView)

            let hitResults = arView.hitTest(location, options: [
                .searchMode: SCNHitTestSearchMode.all.rawValue,
                .ignoreHiddenNodes: true,
            ])

            for hit in hitResults {
                if hit.node.name == "selectionCage" { continue }
                if let placedNode = findPlacedParent(hit.node) {
                    selectNode(placedNode)
                    return
                }
            }

            guard let item = selectedItem else { return }

            guard let query = arView.raycastQuery(from: location, allowing: .estimatedPlane, alignment: .any),
                  let result = arView.session.raycast(query).first
            else { return }

            deselectNode()

            if let scene = loadedScenes[item.id] {
                placeModel(scene: scene, at: result, in: arView)
            } else {
                loadAndPlace(item: item, at: result, in: arView)
            }
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let node = selectedNode else { return }

            switch gesture.state {
            case .began:
                initialPinchScale = node.scale.x
            case .changed:
                let newScale = initialPinchScale * Float(gesture.scale)
                let clamped = min(max(newScale, 0.001), 10.0)
                node.scale = SCNVector3(clamped, clamped, clamped)
                updateDimensions()
                updateCage()
            case .ended, .cancelled:
                updateDimensions()
                updateCage()
            default:
                break
            }
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let node = selectedNode else { return }

            switch gesture.state {
            case .began:
                lastPanX = 0
            case .changed:
                let translation = gesture.translation(in: arView)
                let deltaX = translation.x - lastPanX
                lastPanX = translation.x
                // Rotate around Y axis based on horizontal drag
                let angle = Float(deltaX) * 0.01
                node.eulerAngles.y += angle
            default:
                break
            }
        }

        // MARK: Scale

        func applyScaleMultiplier(_ multiplier: Float) {
            guard let node = selectedNode, multiplier > 0 else { return }
            let newScale = node.scale.x * multiplier
            let clamped = min(max(newScale, 0.001), 10.0)
            node.scale = SCNVector3(clamped, clamped, clamped)
            updateDimensions()
            updateCage()
        }

        // MARK: Dimensions

        private func updateDimensions() {
            guard let node = selectedNode else {
                state.selectedDimensions = .zero
                return
            }
            let s = node.scale.x
            state.selectedDimensions = selectedOriginalExtent * s
        }

        private func computeOriginalExtent(for node: SCNNode) -> SIMD3<Float> {
            guard let modelChild = node.childNodes.first else { return .zero }
            let (minVec, maxVec) = modelChild.boundingBox
            return SIMD3<Float>(
                maxVec.x - minVec.x,
                maxVec.y - minVec.y,
                maxVec.z - minVec.z
            )
        }

        // MARK: Selection

        func deleteSelectedNode() {
            removeCage()
            selectedNode?.removeFromParentNode()
            selectedNode = nil
            selectedOriginalExtent = .zero
            state.hasSelectedNode = false
            state.selectedDimensions = .zero
        }

        func deselectNode() {
            removeCage()
            selectedNode = nil
            selectedOriginalExtent = .zero
            state.hasSelectedNode = false
            state.selectedDimensions = .zero
        }

        private func selectNode(_ node: SCNNode) {
            removeCage()
            selectedNode = node
            selectedOriginalExtent = computeOriginalExtent(for: node)
            addCage(to: node)
            state.hasSelectedNode = true
            updateDimensions()
        }

        // MARK: Bounding Box Cage

        private func addCage(to node: SCNNode) {
            guard let modelChild = node.childNodes.first else { return }
            let (minVec, maxVec) = modelChild.boundingBox
            let w = CGFloat(maxVec.x - minVec.x)
            let h = CGFloat(maxVec.y - minVec.y)
            let d = CGFloat(maxVec.z - minVec.z)
            let cx = CGFloat(minVec.x + maxVec.x) / 2
            let cy = CGFloat(minVec.y + maxVec.y) / 2
            let cz = CGFloat(minVec.z + maxVec.z) / 2

            let cage = SCNNode()
            cage.name = "selectionCage"

            let edgeRadius: CGFloat = max(w, h, d) * 0.005
            let color = Self.cageColor

            func addEdge(from a: SIMD3<Float>, to b: SIMD3<Float>) {
                let diff = b - a
                let length = CGFloat(simd_length(diff))
                let cylinder = SCNCylinder(radius: edgeRadius, height: length)
                let mat = SCNMaterial()
                mat.diffuse.contents = color
                mat.emission.contents = color
                mat.transparency = 0.8
                cylinder.materials = [mat]

                let edgeNode = SCNNode(geometry: cylinder)
                let mid = (a + b) / 2
                edgeNode.position = SCNVector3(mid.x, mid.y, mid.z)

                let up = SIMD3<Float>(0, 1, 0)
                let dir = simd_normalize(diff)
                let cross = simd_cross(up, dir)
                let dot = simd_dot(up, dir)
                if simd_length(cross) > 0.0001 {
                    let angle = acos(min(max(dot, -1), 1))
                    edgeNode.rotation = SCNVector4(cross.x, cross.y, cross.z, angle)
                } else if dot < 0 {
                    edgeNode.rotation = SCNVector4(1, 0, 0, Float.pi)
                }
                edgeNode.name = "selectionCage"
                cage.addChildNode(edgeNode)
            }

            let sphereRadius = edgeRadius * 2.5
            let corners: [SIMD3<Float>] = [
                SIMD3(Float(cx - w/2), Float(cy - h/2), Float(cz - d/2)),
                SIMD3(Float(cx + w/2), Float(cy - h/2), Float(cz - d/2)),
                SIMD3(Float(cx - w/2), Float(cy + h/2), Float(cz - d/2)),
                SIMD3(Float(cx + w/2), Float(cy + h/2), Float(cz - d/2)),
                SIMD3(Float(cx - w/2), Float(cy - h/2), Float(cz + d/2)),
                SIMD3(Float(cx + w/2), Float(cy - h/2), Float(cz + d/2)),
                SIMD3(Float(cx - w/2), Float(cy + h/2), Float(cz + d/2)),
                SIMD3(Float(cx + w/2), Float(cy + h/2), Float(cz + d/2)),
            ]

            for corner in corners {
                let sphere = SCNSphere(radius: sphereRadius)
                let mat = SCNMaterial()
                mat.diffuse.contents = color
                mat.emission.contents = color
                mat.transparency = 0.9
                sphere.materials = [mat]
                let sphereNode = SCNNode(geometry: sphere)
                sphereNode.position = SCNVector3(corner.x, corner.y, corner.z)
                sphereNode.name = "selectionCage"
                cage.addChildNode(sphereNode)
            }

            // Bottom edges
            addEdge(from: corners[0], to: corners[1])
            addEdge(from: corners[0], to: corners[4])
            addEdge(from: corners[1], to: corners[5])
            addEdge(from: corners[4], to: corners[5])
            // Top edges
            addEdge(from: corners[2], to: corners[3])
            addEdge(from: corners[2], to: corners[6])
            addEdge(from: corners[3], to: corners[7])
            addEdge(from: corners[6], to: corners[7])
            // Verticals
            addEdge(from: corners[0], to: corners[2])
            addEdge(from: corners[1], to: corners[3])
            addEdge(from: corners[4], to: corners[6])
            addEdge(from: corners[5], to: corners[7])

            // Rotation arrow indicator at the top
            let arrowTorus = SCNTorus(ringRadius: CGFloat(max(w, d)) * 0.6, pipeRadius: edgeRadius * 1.5)
            let arrowMat = SCNMaterial()
            arrowMat.diffuse.contents = color
            arrowMat.emission.contents = color
            arrowMat.transparency = 0.6
            arrowTorus.materials = [arrowMat]
            let arrowNode = SCNNode(geometry: arrowTorus)
            arrowNode.position = SCNVector3(Float(cx), maxVec.y + Float(h) * 0.15, Float(cz))
            arrowNode.name = "selectionCage"
            // Slow rotation to hint it's draggable
            let hint = SCNAction.repeatForever(SCNAction.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 4))
            arrowNode.runAction(hint)
            cage.addChildNode(arrowNode)

            // Pulse
            let fadeOut = SCNAction.fadeOpacity(to: 0.4, duration: 0.8)
            let fadeIn = SCNAction.fadeOpacity(to: 1.0, duration: 0.8)
            cage.runAction(SCNAction.repeatForever(SCNAction.sequence([fadeOut, fadeIn])))

            modelChild.addChildNode(cage)
            boundingBoxNode = cage
        }

        private func updateCage() {
            removeCage()
            if let node = selectedNode {
                addCage(to: node)
            }
        }

        private func removeCage() {
            boundingBoxNode?.removeFromParentNode()
            boundingBoxNode = nil
        }

        private func findPlacedParent(_ node: SCNNode) -> SCNNode? {
            var current: SCNNode? = node
            while let parent = current?.parent {
                if parent == arView?.scene.rootNode {
                    return current
                }
                current = parent
            }
            return nil
        }

        // MARK: Loading & Placing

        private func loadAndPlace(item: SpaceItem, at result: ARRaycastResult, in arView: ARSCNView) {
            guard let urlString = item.modelFileUrl, let url = URL(string: urlString) else { return }

            let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            let glbPath = cacheDir.appendingPathComponent("\(item.id.uuidString).glb")

            let loadBlock: (URL) -> Void = { [weak self] fileURL in
                GLTFAsset.load(with: fileURL, options: [:]) { _, status, maybeAsset, _, _ in
                    guard status == .complete, let asset = maybeAsset else { return }
                    let source = GLTFSCNSceneSource(asset: asset)
                    guard let scene = source.defaultScene else { return }
                    DispatchQueue.main.async {
                        self?.loadedScenes[item.id] = scene
                        self?.placeModel(scene: scene, at: result, in: arView)
                    }
                }
            }

            if FileManager.default.fileExists(atPath: glbPath.path) {
                loadBlock(glbPath)
            } else {
                Task {
                    do {
                        let (tempURL, _) = try await URLSession.shared.download(from: url)
                        try? FileManager.default.removeItem(at: glbPath)
                        try FileManager.default.moveItem(at: tempURL, to: glbPath)
                        loadBlock(glbPath)
                    } catch {
                        print("AR: failed to download model: \(error)")
                    }
                }
            }
        }

        private func placeModel(scene: SCNScene, at result: ARRaycastResult, in arView: ARSCNView) {
            let clonedNode = scene.rootNode.clone()

            let (minVec, maxVec) = clonedNode.boundingBox
            let extent = max(maxVec.x - minVec.x, maxVec.y - minVec.y, maxVec.z - minVec.z)
            let desiredSize: Float = 0.2
            let scaleFactor = extent > 0 ? desiredSize / extent : 1.0
            clonedNode.scale = SCNVector3(scaleFactor, scaleFactor, scaleFactor)

            let center = SCNVector3(
                (minVec.x + maxVec.x) / 2,
                minVec.y,
                (minVec.z + maxVec.z) / 2
            )
            clonedNode.pivot = SCNMatrix4MakeTranslation(center.x, center.y, center.z)

            let anchorNode = SCNNode()
            anchorNode.simdWorldTransform = result.worldTransform
            anchorNode.addChildNode(clonedNode)
            arView.scene.rootNode.addChildNode(anchorNode)
        }
    }
}
