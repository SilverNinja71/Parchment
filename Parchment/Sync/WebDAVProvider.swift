import Foundation

/// Any WebDAV server: Nextcloud, ownCloud, Synology, QNAP, Koofr, Box (WebDAV), etc.
@MainActor
final class WebDAVProvider: CloudProvider {
    struct Credentials: Codable {
        var server: URL
        var username: String
        var password: String
    }

    let service = CloudService.webDAV
    private var credentials: Credentials?
    private static let keychainKey = "webdav"

    init() {
        credentials = Keychain.codable(Credentials.self, for: Self.keychainKey)
    }

    var isSignedIn: Bool { credentials != nil }

    /// Checks the server and password, then stores them in the Keychain.
    func signIn(server: String, username: String, password: String) async throws {
        var address = server.trimmingCharacters(in: .whitespacesAndNewlines)
        if !address.lowercased().hasPrefix("http") { address = "https://" + address }
        if !address.hasSuffix("/") { address += "/" }
        guard let url = URL(string: address), url.host != nil else {
            throw ParchmentError.sync("That server address doesn't look right.")
        }
        let candidate = Credentials(server: url, username: username, password: password)
        _ = try await propfind(url, depth: 0, credentials: candidate)
        credentials = candidate
        Keychain.setCodable(candidate, for: Self.keychainKey)
    }

    func signOut() {
        credentials = nil
        Keychain.delete(Self.keychainKey)
    }

    func accountName() async throws -> String {
        guard let credentials else { throw notSignedIn }
        return "\(credentials.username) @ \(credentials.server.host ?? "server")"
    }

    func rootFolder() -> RemoteFolder {
        let server = credentials?.server
        let name = server?.host ?? "WebDAV"
        return RemoteFolder(id: server?.absoluteString ?? "", name: name, displayPath: name)
    }

    func list(_ folder: RemoteFolder) async throws -> [RemoteItem] {
        guard let credentials, let url = URL(string: folder.id) else { throw notSignedIn }
        let own = url.standardized.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return try await propfind(url, depth: 1, credentials: credentials).filter {
            URL(string: $0.id)?.standardized.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) != own
        }
    }

    func createFolder(named name: String, in folder: RemoteFolder) async throws -> RemoteFolder {
        guard let credentials, let url = URL(string: folder.id + name.urlPathSegmentEncoded + "/") else { throw notSignedIn }
        var request = URLRequest(url: url)
        request.httpMethod = "MKCOL"
        try await HTTP.send(authorized(request, credentials))
        return folder.child(RemoteItem(id: url.absoluteString, name: name, isFolder: true))
    }

    func upload(_ data: Data, named name: String, to folder: RemoteFolder, replacing existing: RemoteItem?) async throws -> RemoteItem {
        guard let credentials, let url = URL(string: existing?.id ?? folder.id + name.urlPathSegmentEncoded) else { throw notSignedIn }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        try await HTTP.send(authorized(request, credentials))
        // Ask the server for its timestamp so later comparisons use the server's clock.
        let stored = try? await propfind(url, depth: 0, credentials: credentials).first
        return RemoteItem(id: url.absoluteString, name: name, isFolder: false,
                          modified: stored?.modified ?? Date(), size: data.count)
    }

    func download(_ item: RemoteItem) async throws -> Data {
        guard let credentials, let url = URL(string: item.id) else { throw notSignedIn }
        return try await HTTP.send(authorized(URLRequest(url: url), credentials)).0
    }

    // MARK: - WebDAV plumbing

    private var notSignedIn: Error { ParchmentError.sync("You're signed out of your WebDAV server.") }

    private func authorized(_ request: URLRequest, _ credentials: Credentials) -> URLRequest {
        var request = request
        let token = Data("\(credentials.username):\(credentials.password)".utf8).base64EncodedString()
        request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func propfind(_ url: URL, depth: Int, credentials: Credentials) async throws -> [RemoteItem] {
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue("\(depth)", forHTTPHeaderField: "Depth")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("""
        <?xml version="1.0" encoding="utf-8"?>
        <d:propfind xmlns:d="DAV:"><d:prop>
        <d:displayname/><d:getlastmodified/><d:getcontentlength/><d:resourcetype/>
        </d:prop></d:propfind>
        """.utf8)
        let (data, _) = try await HTTP.send(authorized(request, credentials))
        return MultistatusParser.parse(data, base: url)
    }
}

/// Parses a WebDAV `207 Multi-Status` PROPFIND response.
private final class MultistatusParser: NSObject, XMLParserDelegate {
    private struct Entry {
        var href = "", displayName = "", modified = "", length = ""
        var isCollection = false
    }

    private var entries: [Entry] = []
    private var current: Entry?
    private var text = ""

    static func parse(_ data: Data, base: URL) -> [RemoteItem] {
        let delegate = MultistatusParser()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate
        parser.parse()
        return delegate.entries.compactMap { entry in
            guard let url = URL(string: entry.href, relativeTo: base)?.absoluteURL else { return nil }
            let name = entry.displayName.isEmpty ? url.lastPathComponent : entry.displayName
            return RemoteItem(id: url.absoluteString, name: name, isFolder: entry.isCollection,
                              modified: CloudDate.parse(entry.modified), size: Int(entry.length))
        }
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        text = ""
        if elementName == "response" { current = Entry() }
        if elementName == "collection" { current?.isCollection = true }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "href": current?.href = value
        case "displayname": current?.displayName = value
        case "getlastmodified": current?.modified = value
        case "getcontentlength": current?.length = value
        case "response":
            if let current { entries.append(current) }
            current = nil
        default: break
        }
    }
}
