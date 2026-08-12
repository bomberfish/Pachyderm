//
//  ErrorPresenter.swift
//  Pachyderm
//

import Observation
import SwiftUI

/// Gets an error from each part of the app. It shows the error in one alert.
///
/// This class replaces the `UIApplication.shared.alertError(…)` functions. Those
/// functions used the root view controller of the key window. Thus they did
/// nothing when the app showed a different view: a sheet, the OAuth browser or
/// a second alert.
@MainActor
@Observable
final class ErrorPresenter {
    struct Presented: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let detail: String?
    }

    private(set) var presented: Presented?

    func present(_ error: any Error, title: String = "Something went wrong") {
        // A cancel operation is not an error. A request for a cell that leaves
        // the screen must show no alert. A closed sign-in sheet also must show
        // no alert.
        if error is CancellationError { return }
        if let urlError = error as? URLError, urlError.code == .cancelled { return }
        if (error as? MastoAuthError)?.isCancellation == true { return }

        presented = Presented(
            title: title,
            message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription,
            detail: (error as? LocalizedError)?.failureReason
        )
    }

    func present(message: String, title: String = "Something went wrong") {
        presented = Presented(title: title, message: message, detail: nil)
    }

    func dismiss() { presented = nil }
}

extension View {
    /// Adds the one alert. The alert shows each error from `presenter`.
    func errorAlert(_ presenter: ErrorPresenter) -> some View {
        modifier(ErrorAlertModifier(presenter: presenter))
    }
}

private struct ErrorAlertModifier: ViewModifier {
    let presenter: ErrorPresenter

    func body(content: Content) -> some View {
        content.alert(
            presenter.presented?.title ?? "",
            isPresented: Binding(
                get: { presenter.presented != nil },
                set: { if !$0 { presenter.dismiss() } }
            ),
            presenting: presenter.presented
        ) { _ in
            Button("OK", role: .cancel) { presenter.dismiss() }
        } message: { presented in
            Text(presented.detail.map { "\(presented.message)\n\n\($0)" } ?? presented.message)
        }
    }
}
