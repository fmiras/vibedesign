import PhotosUI
import SwiftData
import SwiftUI

struct CaptureView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(BackgroundGenerationManager.self) private var generationManager
    @State private var camera = CameraManager()
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isProcessing = false
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

            Button {
                camera.toggleTorch()
            } label: {
                Image(systemName: camera.isTorchOn ? "bolt.fill" : "bolt.slash.fill")
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
            saveAndDismiss(data: data)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func handlePickedPhoto(_ pickerItem: PhotosPickerItem) async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        do {
            guard let image = try await pickerItem.loadTransferable(type: PhotoPickerImage.self) else { return }
            saveAndDismiss(data: image.data)
        } catch {
            self.error = error.localizedDescription
        }
        selectedPhoto = nil
    }

    /// Save JPEG locally, create SwiftData item, kick off background processing, and dismiss.
    private func saveAndDismiss(data: Data) {
        guard let uiImage = UIImage(data: data),
              let imageData = uiImage.jpegData(compressionQuality: 0.85)
        else {
            self.error = "Could not process image"
            return
        }

        let filename = "capture-\(UUID().uuidString.prefix(8)).jpg"

        // Save image to Documents/images/
        let imageFile = "\(UUID().uuidString).jpg"
        let imageURL = SpaceItem.imagesDirectory.appendingPathComponent(imageFile)
        do {
            try imageData.write(to: imageURL)
        } catch {
            self.error = "Could not save image: \(error.localizedDescription)"
            return
        }

        let item = SpaceItem(name: filename, imageUrl: "")
        item.status = "uploading"
        item.localImagePath = imageFile
        modelContext.insert(item)

        // Start background upload + generation
        generationManager.process(item)

        // Dismiss capture sheet immediately
        dismiss()
    }
}
