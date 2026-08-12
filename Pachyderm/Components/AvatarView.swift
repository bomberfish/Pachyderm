//
//  AvatarView.swift
//  Pachyderm
//
//  Created by Hariz Shirazi on 2025-06-13.
//

import SwiftUI

enum AvatarSize: CGFloat, Sendable {
    case xs = 20
    case small = 32
    case regular = 44
    case large = 76
}

struct AvatarView: View {
    let account: Mastodon.Account
    let size: AvatarSize

    init(account: Mastodon.Account, size: AvatarSize = .regular) {
        self.account = account
        self.size = size
    }

    var body: some View {
        RemoteImage(
            url: account.avatarURL,
            targetSize: CGSize(width: size.rawValue, height: size.rawValue)
        ) {
            Circle().fill(.quaternary)
        }
        .frame(width: size.rawValue, height: size.rawValue)
        .clipShape(Circle())
        .accessibilityLabel("Avatar of \(account.bestDisplayName)")
    }
}

#Preview {
    HStack {
        ForEach([AvatarSize.xs, .small, .regular, .large], id: \.rawValue) { size in
            AvatarView(account: .preview, size: size)
        }
    }
    .padding()
    .previewEnvironment()
}
