//
//  StreamingCenter.swift
//  Pachyderm
//

import Foundation
import Observation
import os

/// The one socket that the whole app shares.
///
/// The `user` channel carries the new posts of the home timeline, the deletes,
/// the edits, the notifications and the conversations. Four screens thus need
/// one connection. A monitor inside each screen would open four sockets to the
/// same channel, and several servers refuse the later ones.
///
/// A screen registers a closure under an id. The center holds the socket, and
/// it opens a new one when the credentials or the address of the instance
/// change.
@MainActor
@Observable
final class StreamingCenter {
    private let api: MastoAPI

    private var monitor: MastodonStreamMonitor?
    private var handlers: [String: @MainActor (Mastodon.StreamEvent) async -> Void] = [:]
    private var reconnectHandlers: [String: @MainActor () async -> Void] = [:]

    /// True between `start()` and `stop()`. The scene phase sets it.
    private var isActive = false

    /// True when `stop()` closed a working socket. The events of the gap are
    /// gone, thus each screen loads its first page again at the next start.
    private var needsGapFill = false

    /// What the current socket uses. The app compares against these values, and
    /// it keeps the socket when nothing changed. `/api/v1/instance` lands after
    /// the first connection, thus this test runs more than one time.
    private var connectedCredentials: MastodonCredentials?
    private var connectedURL: URL?

    init(api: MastoAPI) {
        self.api = api
    }

    var state: MastodonStreamMonitor.State { monitor?.state ?? .idle }

    // MARK: - Registration

    /// Registers one screen.
    ///
    /// The id makes each registration unique. A second appearance of the same
    /// screen thus replaces its earlier closure instead of adding a copy.
    ///
    /// - Parameter onReconnect: Runs after the socket comes back. The screen
    ///   saw none of the events in the gap, thus it must load its first page
    ///   again.
    func addHandler(
        _ id: String,
        onReconnect: (@MainActor () async -> Void)? = nil,
        _ handler: @MainActor @escaping (Mastodon.StreamEvent) async -> Void
    ) {
        handlers[id] = handler
        reconnectHandlers[id] = onReconnect
        connectIfNeeded()
    }

    func removeHandler(_ id: String) {
        handlers[id] = nil
        reconnectHandlers[id] = nil
    }

    // MARK: - Lifetime

    /// The app calls this when the scene becomes active, and again after the
    /// details of the instance arrive.
    func start() {
        isActive = true
        connectIfNeeded()

        guard needsGapFill, monitor != nil else { return }
        needsGapFill = false
        let handlers = reconnectHandlers.values
        Task {
            for handler in handlers {
                await handler()
            }
        }
    }

    /// The app calls this when the scene goes to the background.
    ///
    /// iOS suspends the process there and closes each socket anyway. An
    /// explicit close costs no battery, and it gives the app a known state at
    /// the next start.
    func stop() {
        isActive = false
        guard monitor != nil else { return }
        monitor?.stop()
        monitor = nil
        connectedCredentials = nil
        connectedURL = nil
        needsGapFill = true
        Log.streaming.info("The shared socket is closed.")
    }

    private func connectIfNeeded() {
        guard isActive, !handlers.isEmpty, api.isAuthenticated, api.supportsStreaming else { return }

        let streaming = api.streaming()
        let url = try? streaming.resolvedURL()

        // Compare the resolved addresses and not the advertised ones. Most
        // instances advertise the address that the app would build anyway, and
        // the socket must survive that discovery.
        if monitor != nil, connectedCredentials == api.credentials, connectedURL == url {
            return
        }

        monitor?.stop()
        connectedCredentials = api.credentials
        connectedURL = url

        let monitor = MastodonStreamMonitor(streaming: streaming, kind: .user)
        monitor.onReconnect = { [weak self] in
            guard let self else { return }
            for handler in self.reconnectHandlers.values {
                await handler()
            }
        }
        // Each handler runs in turn and the loop waits for it. The order of the
        // posts in a burst thus survives the trip to the buffer of a list.
        monitor.start { [weak self] event in
            guard let self else { return }
            for handler in self.handlers.values {
                await handler(event)
            }
        }
        self.monitor = monitor
        Log.streaming.info("The shared socket is open on the user channel.")
    }
}
