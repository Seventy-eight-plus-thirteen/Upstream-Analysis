//
//  Mediacl_Academic_InterpreterApp.swift
//  Mediacl Academic Interpreter
//
//  Created by wty on 2026/4/18.
//

import SwiftUI
import CoreData

@main
struct Mediacl_Academic_InterpreterApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
