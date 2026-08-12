//
//  PachydermApp.swift
//  Pachyderm
//
//  Created by Hariz Shirazi on 2025-06-12.
//

import SwiftUI


@main
struct PachydermApp: App {
    @State private var api = MastoAPI()
    @State private var errors = ErrorPresenter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(api)
                .environment(errors)
                .errorAlert(errors)
        }
    }
}
