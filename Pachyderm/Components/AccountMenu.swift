//
//  AccountMenu.swift
//  Pachyderm
//
//  Created by Hariz Shirazi on 2025-06-13.
//

import SwiftUI

/// The avatar button at the top right of each tab.
struct AccountMenu: View {
    @Environment(MastoAPI.self) private var api
    @Environment(Navigator.self) private var navigator

    @State private var isConfirmingSignOut = false

    var body: some View {
        Menu {
            if let me = api.currentAccount {
                Section(me.acct) {
                    Button("My Profile", systemImage: "person.crop.circle") {
                        navigator.open(me)
                    }
                }
            }
            Button("Settings", systemImage: "gear") {}
                .disabled(true)
            Section {
                Button("Log Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    isConfirmingSignOut = true
                }
            } header: {
                // The fork of the server controls the available features. Thus
                // show the name of the fork after the app finds it.
                if api.capabilities.isDetected {
                    Text("\(api.host) · \(api.capabilities.summary)")
                }
            }
        } label: {
            label
                .accessibilityLabel("Account menu")
        }
        .confirmationDialog(
            "Log out of \(api.host)?",
            isPresented: $isConfirmingSignOut,
            titleVisibility: .visible
        ) {
            // A sign-out operation deletes the credentials of the client.
            // `RootView` looks at those credentials. The earlier code called
            // `login(instanceDomain: "", accessToken: "")`, and no view saw
            // the result.
            Button("Log Out", role: .destructive) { api.logOut() }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var label: some View {
        if let me = api.currentAccount {
            AvatarView(account: me, size: .small)
        } else {
            Circle()
                .fill(.quaternary)
                .frame(width: AvatarSize.small.rawValue, height: AvatarSize.small.rawValue)
                .overlay { Image(systemName: "person.fill").foregroundStyle(.secondary) }
        }
    }
}
