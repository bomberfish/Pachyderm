//
//  ComposeView.swift
//  Pachyderm
//
//  Created by Hariz Shirazi on 2025-07-07.
//

import SwiftUI


struct ComposeView: View {
    var inReplyTo: Mastodon.Status?
    var onPosted: (Mastodon.Status) -> Void = { _ in }

    @Environment(MastoAPI.self) private var api
    @Environment(ErrorPresenter.self) private var errors
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var spoilerText = ""
    @State private var hasContentWarning = false
    @State private var visibility: Mastodon.Visibility = .public
    @State private var isPosting = false

    @FocusState private var focus: Field?

    private enum Field: Hashable { case text, spoiler }

    @State var characterLimit = 500

    private var remaining: Int {
        characterLimit - text.count - (hasContentWarning ? spoilerText.count : 0)
    }

    private var canPost: Bool {
        !isPosting
            && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && remaining >= 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let inReplyTo {
                        replyContext(inReplyTo)
                    }

                    if hasContentWarning {
                        TextField("Write your warning here", text: $spoilerText)
                            .focused($focus, equals: .spoiler)
                            .submitLabel(.next)
                            .onSubmit { focus = .text }
                            .fancyInput()
                    }

                    HStack(alignment: .top, spacing: 10) {
                        if let me = api.currentAccount {
                            AvatarView(account: me, size: .regular)
                        }

                        TextField(
                            inReplyTo == nil ? "What's on your mind?" : "Write your reply",
                            text: $text,
                            axis: .vertical
                        )
                        .font(.body)
                        .focused($focus, equals: .text)
                        .frame(minHeight: 120, alignment: .topLeading)
                    }
                }
                .padding()
            }
            .navigationTitle(inReplyTo == nil ? "New Post" : "Reply")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .disabled(isPosting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        post()
                    } label: {
                        if isPosting {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Post", systemImage: "paperplane.fill")
                        }
                    }
                    .buttonStyle(.glassBackportProminent)
                    .disabled(!canPost)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Button("Content Warning", systemImage: "exclamationmark.triangle") {
                        withAnimation(.snappy) {
                            hasContentWarning.toggle()
                            if hasContentWarning {
                                focus = .spoiler
                            } else {
                                spoilerText = ""
                            }
                        }
                    }
                    .symbolVariant(hasContentWarning ? .fill : .none)

                    Picker("Visibility", selection: $visibility) {
                        ForEach(Mastodon.Visibility.composable, id: \.self) { option in
                            Label(option.description, systemImage: option.icon).tag(option)
                        }
                    }
                    .pickerStyle(.menu)

                    Spacer()

                    Text(remaining, format: .number)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(remaining < 0 ? .red : .secondary)
                        .accessibilityLabel("\(remaining) characters remaining")
                }
            }
            .onAppear {
                characterLimit = api.instance?.maxPostCharacters ?? 500
                if let inReplyTo, let replied = inReplyTo.visibility, replied != .unknown {
                    visibility = replied
                }
                focus = .text
            }
            .interactiveDismissDisabled(isPosting)
        }
    }

    private func replyContext(_ status: Mastodon.Status) -> some View {
        HStack(alignment: .top, spacing: 8) {
            AvatarView(account: status.account, size: .small)
            VStack(alignment: .leading, spacing: 2) {
                Text("Replying to \(status.account.bestDisplayName)")
                    .font(.subheadline.weight(.medium))
                RichText(html: status.html, emoji: status.emojis)
                    .font(.footnote)
                    .lineLimit(3)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func post() {
        guard canPost else { return }
        isPosting = true
        focus = nil

        Task {
            do {
                let created = try await api.post(
                    text,
                    visibility: visibility,
                    spoilerText: hasContentWarning ? spoilerText : nil,
                    inReplyTo: inReplyTo?.id
                )
                Haptic.shared.notify(.success)
                onPosted(created)
                dismiss()
            } catch {
                isPosting = false
                Haptic.shared.notify(.error)
                errors.present(error, title: "Couldn't post")
            }
        }
    }
}

#Preview("Compose") {
    ComposeView()
        .previewEnvironment()
}

#Preview("Reply") {
    ComposeView(inReplyTo: .preview)
        .previewEnvironment()
}
