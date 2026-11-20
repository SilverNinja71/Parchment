import Foundation

/// Unified self-hosted Amphi / BelloBook Server ("One Server, Sync All") provider.
/// Connects to a user's self-hosted server (e.g. Amphi `.jar` server or BelloBook REST/WebDAV endpoint)
/// to sync notebooks, media vault attachments, audio, and photos from one place.
@MainActor
final class AmphiServerProvider: CloudProvider {
    struct Credentials: Codable {
        var server: URL
        var username: String
        var password: String
    }

    let service = CloudService.amphiServer
    private var credentials: Credentials?
    private static let keychainKey = "amphiServer"

    init() {
        credentials = Keychain.codable(Credentials.self, for: Self.keychainKey)
    }

    var isSignedIn: Bool { credentials != nil }

    func signIn(server: String, username: String, password: String) async throws {
        var address = server.trimmingCharacters(in: .whitespacesAndNewlines)
        if !address.lowercased().hasPrefix("http") { address = "http://" + address }
        if !address.hasSuffix("/") { address += "/" }
        guard let url = URL(string: address), url.host != nil else {
            throw ParchmentError.sync("That server address doesn't look right.")
        }
        // Verify reachability via HEAD/GET
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        let candidate = Credentials(server: url, username: username, password: password)
        _ = try await HTTP.send(authorized(request, candidate))
        credentials = candidate
        Keychain.setCodable(candidate, for: Self.keychainKey)
    }

    func signOut() {
        credentials = nil
        Keychain.delete(Self.keychainKey)
    }

    func accountName() async throws -> String {
        guard let credentials else { throw notSignedIn }
        let user = credentials.username.isEmpty ? "Self-Hosted" : credentials.username
        return "\(user) @ \(credentials.server.host ?? "Amphi Server")"
    }

    func rootFolder() -> RemoteFolder {
        let host = credentials?.server.host ?? "BelloBook Server"
        return RemoteFolder(id: credentials?.server.absoluteString ?? "", name: host, displayPath: "\(host) › BelloBook")
    }

    func list(_ folder: RemoteFolder) async throws -> [RemoteItem] {
        guard let credentials, let url = URL(string: folder.id) else { throw notSignedIn }
        var request = URLRequest(url: url.appendingPathComponent("notes"))
        request.httpMethod = "GET"
        let (data, _) = try await HTTP.send(authorized(request, credentials))
        if let decoded = try? JSONDecoder().decode([ServerFileEntry].self, from: data) {
            return decoded.map {
                RemoteItem(id: url.appendingPathComponent($0.path).absoluteString,
                           name: $0.name,
                           isFolder: $0.isFolder,
                           modified: $0.modified,
                           size: $0.size)
            }
        }
        return []
    }

    func createFolder(named name: String, in folder: RemoteFolder) async throws -> RemoteFolder {
        guard let credentials, let url = URL(string: folder.id) else { throw notSignedIn }
        let target = url.appendingPathComponent(name)
        var request = URLRequest(url: target)
        request.httpMethod = "POST"
        _ = try? await HTTP.send(authorized(request, credentials))
        return folder.child(RemoteItem(id: target.absoluteString + "/", name: name, isFolder: true))
    }

    func upload(_ data: Data, named name: String, to folder: RemoteFolder, replacing existing: RemoteItem?) async throws -> RemoteItem {
        guard let credentials, let base = URL(string: existing?.id ?? folder.id) else { throw notSignedIn }
        let target = existing != nil ? base : base.appendingPathComponent(name)
        var request = URLRequest(url: target)
        request.httpMethod = "PUT"
        request.httpBody = data
        _ = try await HTTP.send(authorized(request, credentials))
        return RemoteItem(id: target.absoluteString, name: name, isFolder: false, modified: Date(), size: data.count)
    }

    func download(_ item: RemoteItem) async throws -> Data {
        guard let credentials, let url = URL(string: item.id) else { throw notSignedIn }
        let (data, _) = try await HTTP.send(authorized(URLRequest(url: url), credentials))
        return data
    }

    private func authorized(_ request: URLRequest, _ creds: Credentials) -> URLRequest {
        var req = request
        if !creds.username.isEmpty || !creds.password.isEmpty {
            let token = Data("\(creds.username):\(creds.password)".utf8).base64EncodedString()
            req.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    private var notSignedIn: Error {
        ParchmentError.sync("Not connected to a BelloBook / Amphi server.")
    }

    private struct ServerFileEntry: Codable {
        var id: String
        var name: String
        var path: String
        var isFolder: Bool
        var modified: Date?
        var size: Int?
    }
}
