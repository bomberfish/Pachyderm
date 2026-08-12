//
//  Log.swift
//  Pachyderm
//

import os

/// The loggers for each part of the app.
///
/// The earlier code used the `print` function in each file. It also printed the
/// full body of an HTTP response. That operation is slow, and it can put an
/// access token into the logs of the device. A `Logger` object writes nothing in
/// a release build, except after a request from the user. It also hides each
/// value in a message.
nonisolated enum Log {
    private static let subsystem = "ca.bomberfish.Pachyderm"

    static let ui = Logger(subsystem: subsystem, category: "ui")
    static let auth = Logger(subsystem: subsystem, category: "auth")
}
