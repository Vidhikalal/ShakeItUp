//
//  VYBEWATCHApp.swift
//  VYBEWATCH Watch App
//
//  Created by Teresa Akinbodun on 2026-01-18.
//

import SwiftUI

@main
struct VYBEWATCH_Watch_AppApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
    init() {
        _ = WatchHapticsReceiver.shared
    }

}
