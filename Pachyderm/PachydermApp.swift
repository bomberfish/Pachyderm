//
//  PachydermApp.swift
//  Pachyderm
//
//  Created by Hariz Shirazi on 2025-06-12.
//

import SwiftUI


@main
struct PachydermApp: App {
    @State private var api: MastoAPI
    @State private var errors = ErrorPresenter()

    /// The socket that each screen shares. It belongs to the app and not to a
    /// screen, because one channel feeds the timeline, the notifications, the
    /// messages and the badge.
    @State private var streaming: StreamingCenter

    init() {
        let api = MastoAPI()
        _api = State(initialValue: api)
        _streaming = State(initialValue: StreamingCenter(api: api))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(api)
                .environment(errors)
                .environment(streaming)
                .errorAlert(errors)
        }
    }
}
