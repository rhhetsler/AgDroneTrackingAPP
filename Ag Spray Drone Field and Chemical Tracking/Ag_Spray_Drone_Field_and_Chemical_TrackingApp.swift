//
//  Ag_Spray_Drone_Field_and_Chemical_TrackingApp.swift
//  Ag Spray Drone Field and Chemical Tracking
//
//  Created by Reggie Hetsler on 2/6/26.
//

import SwiftUI
import SwiftData

@main
struct Ag_Spray_Drone_Field_and_Chemical_TrackingApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
