//
//  TollFinderApp.swift
//  TollFinder
//
//  Created by Riley Martin on 24/9/2025.
//

import SwiftUI
import CoreData

@main
struct TollFinderApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
