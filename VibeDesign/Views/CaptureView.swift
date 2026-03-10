import PhotosUI
import SwiftData
import SwiftUI

struct CaptureView: View {
    @Environment(\.modelContext) private var modelContext
    @Namespace private var sheetTransition
    @State private var camera = CameraManager()
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var capturedImageData: Data?
    @State private var isProcessing = false
    @State private var processingItem: SpaceItem?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ZStack {
                if camera.isAuthorized {
                    CameraPreview(session: camera.session)
                        .ignoresSafeArea()
                } else {
                    ContentUnavailableView(
                        "Camera Access Required",
                        systemImage: "camera.fill",
                        description: Text("Allow camera access in Settings to capture objects.")
                    )
                }

                VStack {
                    Spacer()
                    captureControls
                }
                .padding(.bottom, 30)
            }
            .navigationTitle("Capture")
            .toolbarVisibility(.hidden, for: .navigationBar)
            .task {
                await camera.requestAccess()
                if camera.isAuthorized {
                    camera.configure()
                    camera.start()
                }
            }
            .onDisappear {
                camera.stop()
            }
            .onChange(of: selectedPhoto) { _, newValue in
                guard let newValue else { return }
                Task { await handlePickedPhoto(newValue) }
            }
            .sheet(item: $processingItem) { item in
                ProcessingView(item: item)
                    .navigationTransition(.zoom(sourceID: "processing", in: sheetTransition))
            }
            .alert("Error", isPresented: .init(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
        }
    }

    private var captureControls: some View {
        HStack(spacing: 24) {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Image(systemName: "photo.on.rectangle")
                    .font(.title2)
                    .frame(width: 56, height: 56)
            }
            .buttonStyle(.glass)

            Button {
                Task { await capturePhoto() }
            } label: {
                Image(systemName: "camera.fill")
                    .font(.system(size: 32))
                    .frame(width: 72, height: 72)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .disabled(isProcessing)
            .matchedTransitionSource(id: "processing", in: sheetTransition)

            Button {
                // placeholder for flash toggle or settings
            } label: {
                Image(systemName: "bolt.slash.fill")
                    .font(.title2)
                    .frame(width: 56, height: 56)
            }
            .buttonStyle(.glass)
        }
    }

    private func capturePhoto() async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        do {
            let data = try await camera.capturePhoto()
            await processImage(data: data)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func handlePickedPhoto(_ pickerItem: PhotosPickerItem) async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        do {
            // Load as UIImage transferable to handle HEIC/HEIF/WebP/PNG automatically
            guard let image = try await pickerItem.loadTransferable(type: PhotoPickerImage.self) else { return }
            await processImage(data: image.data)
        } catch {
            self.error = error.localizedDescription
        }
        selectedPhoto = nil
    }

    private func processImage(data: Data) async {
        // Always convert to JPEG — the Replicate API requires standard image formats
        guard let uiImage = UIImage(data: data),
              let imageData = uiImage.jpegData(compressionQuality: 0.85)
        else {
            self.error = "Could not process image"
            return
        }

        let filename = "capture-\(UUID().uuidString.prefix(8)).jpg"
        let item = SpaceItem(name: filename, imageUrl: "")
        modelContext.insert(item)

        do {
            let publicUrl = try await UploadService.uploadPhoto(imageData, filename: filename)
            item.imageUrl = publicUrl
            item.status = "generating"
            processingItem = item
        } catch {
            item.status = "failed"
            self.error = error.localizedDescription
        }
    }
}
