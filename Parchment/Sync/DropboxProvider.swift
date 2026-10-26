import Foundation

/// Dropbox through the v2 HTTP API.
@MainActor
final class DropboxProvider: OAuthCloudProvider {
    let service = CloudService.dropbox
    let oauth: OAuthClient
    private let api = "https://api.dropboxapi.com/2"
    private let content = "https://content.dropboxapi.com/2"

    init() {
        let appKey = CloudCredentials.dropboxAppKey
        oauth = OAuthClient(configuration: OAuthConfiguration(
            name: "dropbox",
            authorizeURL: URL(string: "https://www.dropbox.com/oauth2/authorize")!,
            tokenURL: URL(string: "https://api.dropboxapi.com/oauth2/token")!,
            clientID: appKey,
            redirectURI: "db-\(appKey)://2/token",
            callbackScheme: "db-\(appKey)",
            scopes: ["account_info.read", "files.metadata.read", "files.content.read", "files.content.write"],
            extraParameters: ["token_access_type": "offline"]))
    }

    private struct Metadata: Decodable {
        let tag: String?
        let name: String
        let path_display: String?
        let server_modified: String?
        let size: Int?

        enum CodingKeys: String, CodingKey {
            case tag = ".tag"
            case name, path_display, server_modified, size
        }

        var item: RemoteItem {
            RemoteItem(id: path_display ?? "/\(name)", name: name, isFolder: tag == "folder",
                       modified: CloudDate.parse(server_modified), size: size)
        }
    }

    func accountName() async throws -> String {
        struct Account: Decodable {
            struct Name: Decodable { let display_name: String }
            let name: Name
            let email: String?
        }
        var request = URLRequest(url: URL(string: "\(api)/users/get_current_account")!)
        request.httpMethod = "POST"
        let (data, _) = try await oauth.send(request)
        let account = try HTTP.decode(Account.self, from: data)
        return account.email ?? account.name.display_name
    }

    func rootFolder() -> RemoteFolder {
        RemoteFolder(id: "", name: "Dropbox", displayPath: "Dropbox")
    }

    func list(_ folder: RemoteFolder) async throws -> [RemoteItem] {
        struct Page: Decodable { let entries: [Metadata]; let cursor: String; let has_more: Bool }
        var (data, _) = try await oauth.send(HTTP.request(URL(string: "\(api)/files/list_folder")!, method: "POST",
                                                          json: ["path": folder.id, "limit": 500]))
        var page = try HTTP.decode(Page.self, from: data)
        var items = page.entries.map(\.item)
        while page.has_more {
            (data, _) = try await oauth.send(HTTP.request(URL(string: "\(api)/files/list_folder/continue")!, method: "POST",
                                                          json: ["cursor": page.cursor]))
            page = try HTTP.decode(Page.self, from: data)
            items += page.entries.map(\.item)
        }
        return items.filter { $0.isFolder || $0.size != nil } // skip deleted entries
    }

    func createFolder(named name: String, in folder: RemoteFolder) async throws -> RemoteFolder {
        struct Result: Decodable { let metadata: Metadata }
        let (data, _) = try await oauth.send(HTTP.request(URL(string: "\(api)/files/create_folder_v2")!, method: "POST",
                                                          json: ["path": "\(folder.id)/\(name)", "autorename": true]))
        var item = try HTTP.decode(Result.self, from: data).metadata.item
        item.isFolder = true
        return folder.child(item)
    }

    func upload(_ data: Data, named name: String, to folder: RemoteFolder, replacing existing: RemoteItem?) async throws -> RemoteItem {
        var request = URLRequest(url: URL(string: "\(content)/files/upload")!)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.apiArg(["path": existing?.id ?? "\(folder.id)/\(name)", "mode": "overwrite", "mute": true]),
                         forHTTPHeaderField: "Dropbox-API-Arg")
        request.httpBody = data
        let (result, _) = try await oauth.send(request)
        return try HTTP.decode(Metadata.self, from: result).item
    }

    func download(_ item: RemoteItem) async throws -> Data {
        var request = URLRequest(url: URL(string: "\(content)/files/download")!)
        request.httpMethod = "POST"
        request.setValue(Self.apiArg(["path": item.id]), forHTTPHeaderField: "Dropbox-API-Arg")
        return try await oauth.send(request).0
    }

    /// Dropbox wants JSON in a header, with every non-ASCII character escaped.
    private static func apiArg(_ value: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: value)) ?? Data()
        let json = String(data: data, encoding: .utf8) ?? "{}"
        // Escaping UTF-16 units also produces correct surrogate pairs for emoji.
        return json.utf16.map { unit in
            unit < 128 ? String(UnicodeScalar(UInt8(unit))) : String(format: "\\u%04x", unit)
        }.joined()
    }
}
