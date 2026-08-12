//
//  SetupView.swift
//  Pachyderm
//
//  Created by Hariz Shirazi on 2025-06-12.
//

import SwiftUI

/// The sign-in screen.
///
/// All the OAuth code is now in `MastoAuth.signIn(host:)`. Thus this screen has
/// only a text field and a button. That change also corrected a fault. The
/// earlier code gave the text of the field to the token request and to the
/// client without a change. The text can include `https://` from the user. Thus
/// each URL after that point was incorrect.
struct SetupView: View {
    @Environment(MastoAPI.self) private var api
    @Environment(ErrorPresenter.self) private var errors

    @State private var host = ""
    @State private var isSigningIn = false
    @FocusState private var isFieldFocused: Bool

    private var canSignIn: Bool {
        !isSigningIn && MastodonCredentials.isValid(host: host)
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "text.bubble")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("Welcome to Pachyderm")
                    .font(.title2.weight(.semibold))
                Text("Enter the domain of your Mastodon instance.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            TextField("mastodon.social", text: $host)
                .textContentType(.URL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .focused($isFieldFocused)
                .onSubmit { if canSignIn { signIn() } }
                .modifier(FancyInputViewModifier())

            Button {
                signIn()
            } label: {
                HStack(spacing: 6) {
                    if isSigningIn {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "person.badge.key")
                    }
                    Text(isSigningIn ? "Signing in…" : "Log in with Mastodon")
                }
                .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.glassBackportProminent)
            .disabled(!canSignIn)

            Spacer()
        }
        .frame(maxWidth: 420)
        .padding()
        .onAppear { isFieldFocused = true }
    }

    private func signIn() {
        guard !isSigningIn else { return }
        isSigningIn = true
        isFieldFocused = false

        Task {
            defer { isSigningIn = false }
            do {
                let token = try await MastoAuth.signIn(host: host)
                try await api.logIn(host: host, accessToken: token)
            } catch {
                errors.present(error, title: "Couldn't sign in")
            }
        }
    }
}

#Preview {
    SetupView()
        .environment(MastoAPI(credentials: MastodonCredentials(host: "", accessToken: nil)))
        .environment(ErrorPresenter())
}
