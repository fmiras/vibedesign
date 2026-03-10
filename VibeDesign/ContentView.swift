//
//  ContentView.swift
//  VibeDesign
//
//  Created by Federico Miras on 08/03/2026.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Capture", systemImage: "camera.fill") {
                CaptureView()
            }

            Tab("Gallery", systemImage: "square.grid.2x2.fill") {
                GalleryView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}

#Preview {
    ContentView()
}
