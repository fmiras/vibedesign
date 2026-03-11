//
//  VibeDesignApp.swift
//  VibeDesign
//
//  Created by Federico Miras on 08/03/2026.
//

import SwiftData
import SwiftUI

@main
struct VibeDesignApp: App {
    @State private var generationManager = BackgroundGenerationManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(generationManager)
        }
        .modelContainer(for: SpaceItem.self)
    }
}
