import Foundation
import CryptoKit
import AuthenticationServices
import SwiftUI

struct OAuthConfiguration {
    /// Short name used for the Keychain entry ("onedrive", "google", "dropbox").
    let name: String
    let authorizeURL: URL
    let tokenURL: URL
    let clientID: String
    let redirectURI: String
    let callbackScheme: String
    let scopes: [String]
    var extraParameters: [String: String] = [:]
}

struct OAuthTokens: Codable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
}

/// OAuth 2.0 sign-in with PKCE using Apple's secure web sign-in sheet.
///
/// The user signs in on the provider's own page (Microsoft, Google, Dropbox), so
/// Parchment never sees their password. Tokens are kept in the Keychain.
@MainActor
final class OAuthClient {
    let configuration: OAuthConfiguration
    private(set) var tokens: OAuthTokens?
    private var refreshTask: Task<OAuthTokens, Error>?

    init(configuration: OAuthConfiguration) {
        self.configuration = configuration
        tokens = Keychain.codable(OAuthTokens.self, for: keychainKey)
    }

    var isSignedIn: Bool { tokens != nil }
    private var keychainKey: String { "oauth.\(configuration.name)" }

    func signIn(using webAuthentication: WebAuthenticationSession) async throws {
        let verifier = Self.randomString(length: 64)
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = Self.randomString(length: 24)

        var components = URLComponents(url: configuration.authorizeURL, resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "scope", value: configuration.scopes.joined(separator: " ")),
        ]
        items += configuration.extraParameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        components.queryItems = items
        guard let url = components.url else { throw ParchmentError.sync("Couldn't build the sign-in address.") }

        let callback = try await webAuthentication.authenticate(using: url, callbackURLScheme: configuration.callbackScheme)
        let query = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { query.first { $0.name == name }?.value }

        if let error = value("error") {
            throw ParchmentError.sync("Sign-in failed: \(value("error_description") ?? error)")
        }
        guard value("state") == state, let code = value("code") else {
            throw ParchmentError.sync("Sign-in was interrupted. Please try again.")
        }
        let tokens = try await requestTokens([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": configuration.redirectURI,
            "client_id": configuration.clientID,
            "code_verifier": verifier,
        ])
        save(tokens)
    }

    func signOut() {
        tokens = nil
        Keychain.delete(keychainKey)
    }

    func accessToken() async throws -> String {
        guard let tokens else {
            throw ParchmentError.sync("You're signed out. Sign in again from Settings → Sync.")
        }
        if tokens.expiresAt > Date().addingTimeInterval(60) { return tokens.accessToken }
        return try await refresh().accessToken
    }

    /// Sends a request with the access token, refreshing it once if the server says it expired.
    @discardableResult
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var authorized = request
        authorized.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        do {
            return try await HTTP.send(authorized)
        } catch let error as HTTPError where error.status == 401 {
            let tokens = try await refresh()
            authorized.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
            return try await HTTP.send(authorized)
        }
    }

    @discardableResult
    private func refresh() async throws -> OAuthTokens {
        if let refreshTask { return try await refreshTask.value }
        guard let refreshToken = tokens?.refreshToken else {
            signOut()
            throw ParchmentError.sync("Your sign-in expired. Sign in again from Settings → Sync.")
        }
        let task = Task {
            try await self.requestTokens([
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
                "client_id": self.configuration.clientID,
            ])
        }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            var refreshed = try await task.value
            if refreshed.refreshToken == nil { refreshed.refreshToken = refreshToken }
            save(refreshed)
            return refreshed
        } catch let error as HTTPError where error.status == 400 || error.status == 401 {
            signOut()
            throw ParchmentError.sync("Your sign-in expired. Sign in again from Settings → Sync.")
        }
    }

    private func requestTokens(_ form: [String: String]) async throws -> OAuthTokens {
        var request = URLRequest(url: configuration.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = HTTP.formBody(form)
        let (data, _) = try await HTTP.send(request)

        struct Response: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Double?
        }
        let response = try HTTP.decode(Response.self, from: data)
        return OAuthTokens(accessToken: response.access_token, refreshToken: response.refresh_token,
                           expiresAt: Date().addingTimeInterval(response.expires_in ?? 3600))
    }

    private func save(_ tokens: OAuthTokens) {
        self.tokens = tokens
        Keychain.setCodable(tokens, for: keychainKey)
    }

    private static func randomString(length: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return String(base64URL(Data(bytes)).prefix(length))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
