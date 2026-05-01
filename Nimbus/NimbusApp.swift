//
//  NimbusApp.swift
//  Nimbus
//
//  Created by Олег Курей on 01.05.2026.
//

import SwiftUI
import CoreData

@main
struct NimbusApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
