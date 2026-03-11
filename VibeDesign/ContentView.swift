//
//  ContentView.swift
//  VibeDesign
//
//  Created by Federico Miras on 08/03/2026.
//

import SwiftUI

enum AppTab: Hashable {
    case gallery, ar, add, settings
}

struct ContentView: View {
    @State private var selectedTab: AppTab = .gallery
    @State private var showCapture = false

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Gallery", systemImage: "square.grid.2x2.fill", value: .gallery) {
                GalleryView(showCapture: $showCapture)
            }

            Tab("AR", systemImage: "arkit", value: .ar) {
                ARPlacementView()
            }

            Tab("Settings", systemImage: "gearshape", value: .settings) {
                SettingsView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .sheet(isPresented: $showCapture) {
            CaptureView()
        }
    }
}

#Preview {
    ContentView()
}
