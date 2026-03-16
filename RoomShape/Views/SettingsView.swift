import SwiftUI

struct SettingsView: View {
    @AppStorage("testMode") private var testMode = true
    @AppStorage("rotateGallery") private var rotateGallery = true
    @AppStorage("useImagePreview") private var useImagePreview = false
    @AppStorage("arUnitCm") private var useCm = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Test Mode", isOn: $testMode)
                } header: {
                    Text("API")
                } footer: {
                    Text("When enabled, requests use mocked responses and don't consume Replicate credits.")
                }

                Section {
                    Toggle("Rotate Objects in Gallery", isOn: $rotateGallery)
                    Toggle("Use Image Preview", isOn: $useImagePreview)
                } header: {
                    Text("Gallery")
                } footer: {
                    Text("Show source photo instead of spinning 3D model in the gallery grid.")
                }

                Section {
                    Picker("Measurement Unit", selection: $useCm) {
                        Text("Centimeters").tag(true)
                        Text("Inches").tag(false)
                    }
                } header: {
                    Text("AR")
                } footer: {
                    Text("Unit used for object dimensions when placing in AR.")
                }
            }
            .navigationTitle("Settings")
        }
    }
}
