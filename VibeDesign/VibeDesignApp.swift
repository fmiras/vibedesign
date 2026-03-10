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
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: SpaceItem.self)
    }
}
