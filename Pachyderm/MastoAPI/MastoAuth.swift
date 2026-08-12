//
//  MastoAuth.swift
//  Pachyderm
//
//  Created by Hariz Shirazi on 2025-06-12.
//

import AuthenticationServices
import Foundation
import UIKit


@MainActor
enum MastoAuth {
    static let redirectURI = "pachyderm://auth"
    static let callbackScheme = "pachyderm"
    static let scopes = "read write follow push"
    static let website = "https://github.com/BomberFish/Pachyderm"

    static func signIn(host rawHost: String) async throws -> String {
        let host = MastodonCredentials.normalize(host: rawHost)
        guard MastodonCredentials.isValid(host: host) else {
            throw MastodonError.invalidHost(rawHost)
        }

        let app = try await registerApp(host: host)
        let code = try await authorize(host: host, clientID: app.clientId)
        let token = try await fetchToken(
            host: host,
            clientID: app.clientId,
            clientSecret: app.clientSecret,
            authCode: code
        )
        return token.accessToken
    }

    // MARK: - Steps

    static func registerApp(host: String) async throws -> AppRegistration {
        try await post(host: host, path: "/api/v1/apps", body: [
            "client_name": "Pachyderm",
            "redirect_uris": redirectURI,
            "scopes": scopes,
            "website": website,
        ])
    }

    static func fetchToken(
        host: String,
        clientID: String,
        clientSecret: String,
        authCode: String
    ) async throws -> TokenResponse {
        try await post(host: host, path: "/oauth/token", body: [
            "grant_type": "authorization_code",
            "code": authCode,
            "client_id": clientID,
            "client_secret": clientSecret,
            "redirect_uri": redirectURI,
            "scope": scopes,
        ])
    }

    /// Shows the authorization page of the instance and gives the code.
    private static func authorize(host: String, clientID: String) async throws -> String {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/oauth/authorize"
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "force_login", value: "true"),
        ]
        guard let url = components.url else { throw MastodonError.invalidHost(host) }

        let contextProvider = PresentationContextProvider()

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                // This line keeps the `contextProvider` object. It is
                // necessary. The `presentationContextProvider` property is a
                // weak reference. Without this line the system releases the
                // provider before the sheet appears.
                _ = contextProvider

                if let error {
                    if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                        continuation.resume(throwing: MastoAuthError.userCancelled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                guard let callbackURL,
                      let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: true)?.queryItems
                else {
                    continuation.resume(throwing: MastoAuthError.authCodeMissing)
                    return
                }
                if let denied = items.first(where: { $0.name == "error" })?.value {
                    continuation.resume(throwing: MastoAuthError.authFailed(denied))
                    return
                }
                guard let code = items.first(where: { $0.name == "code" })?.value else {
                    continuation.resume(throwing: MastoAuthError.authCodeMissing)
                    return
                }
                continuation.resume(returning: code)
            }

            session.presentationContextProvider = contextProvider
            session.prefersEphemeralWebBrowserSession = true

            if !session.start() {
                continuation.resume(throwing: MastoAuthError.authFailed("Couldn't open the sign-in page."))
            }
        }
    }

    // MARK: - Plumbing

    /// The OAuth endpoints are not part of `/api`. Thus they do not use
    /// `MastodonHTTP`.
    private static func post<T: Decodable>(
        host: String,
        path: String,
        body: [String: String]
    ) async throws -> T {
        guard let url = URL(string: "https://\(host)\(path)") else {
            throw MastodonError.invalidHost(host)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MastodonError.transport("The server sent a malformed response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder.mastodon.decode(OAuthError.self, from: data))?.message
            throw MastodonError.server(status: http.statusCode, message: message)
        }

        do {
            return try JSONDecoder.mastodon.decode(T.self, from: data)
        } catch {
            throw MastodonError.decoding(type: String(describing: T.self), underlying: String(describing: error))
        }
    }
}

// MARK: - Wire types

nonisolated struct AppRegistration: Decodable, Sendable {
    let clientId: String
    let clientSecret: String
}

nonisolated struct TokenResponse: Decodable, Sendable {
    let accessToken: String
}

private nonisolated struct OAuthError: Decodable {
    let error: String?
    let errorDescription: String?

    var message: String? { errorDescription ?? error }
}

nonisolated enum MastoAuthError: LocalizedError, Sendable {
    case authCodeMissing
    case authFailed(String)
    case userCancelled

    var errorDescription: String? {
        switch self {
        case .authCodeMissing: "The instance didn't send back an authorization code."
        case .authFailed(let reason): "Sign-in failed: \(reason)"
        case .userCancelled: "Sign-in was cancelled."
        }
    }

    /// A cancel operation is not an error. The app shows no alert for it.
    var isCancellation: Bool {
        if case .userCancelled = self { return true }
        return false
    }
}

// MARK: - Presentation

private final class PresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.firstWindow ?? ASPresentationAnchor()
    }
}
