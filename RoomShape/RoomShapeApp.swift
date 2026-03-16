//
//  RoomShapeApp.swift
//  RoomShape
//
//  Created by Federico Miras on 08/03/2026.
//

import SwiftData
import SwiftUI

@main
struct RoomShapeApp: App {
    @State private var generationManager = BackgroundGenerationManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(generationManager)
        }
        .modelContainer(for: SpaceItem.self)
    }
}
