import Foundation

/// OneDrive (personal, work and school) through Microsoft Graph.
@MainActor
final class OneDriveProvider: OAuthCloudProvider {
    let service = CloudService.oneDrive
    let oauth: OAuthClient
    private let graph = URL(string: "https://graph.microsoft.com/v1.0")!

    init() {
        // Microsoft's standard redirect for mobile apps; it doesn't depend on the bundle ID,
        // so it works the same in Xcode builds and in Swift Playgrounds.
        let scheme = "msal\(CloudCredentials.oneDriveClientID)"
        oauth = OAuthClient(configuration: OAuthConfiguration(
            name: "onedrive",
            authorizeURL: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize")!,
            tokenURL: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/token")!,
            clientID: CloudCredentials.oneDriveClientID,
            redirectURI: "\(scheme)://auth",
            callbackScheme: scheme,
            scopes: ["offline_access", "User.Read", "Files.ReadWrite"],
            extraParameters: ["prompt": "select_account"]))
    }

    private struct DriveItem: Decodable {
        struct Marker: Decodable {}
        let id: String
        let name: String
        let folder: Marker?
        let lastModifiedDateTime: String?
        let size: Int?

        var item: RemoteItem {
            RemoteItem(id: id, name: name, isFolder: folder != nil,
                       modified: CloudDate.parse(lastModifiedDateTime), size: size)
        }
    }

    private struct Page: Decodable {
        let value: [DriveItem]
        let nextLink: String?
        enum CodingKeys: String, CodingKey {
            case value
            case nextLink = "@odata.nextLink"
        }
    }

    func accountName() async throws -> String {
        struct Me: Decodable { let displayName: String?; let userPrincipalName: String? }
        let (data, _) = try await oauth.send(HTTP.request(graph.appendingPathComponent("me")))
        let me = try HTTP.decode(Me.self, from: data)
        return me.userPrincipalName ?? me.displayName ?? "Microsoft account"
    }

    func rootFolder() -> RemoteFolder {
        RemoteFolder(id: "root", name: "OneDrive", displayPath: "OneDrive")
    }

    func list(_ folder: RemoteFolder) async throws -> [RemoteItem] {
        var next: URL? = URL(string: "\(graph.absoluteString)/me/drive/items/\(folder.id)/children?$top=200&$select=id,name,folder,file,lastModifiedDateTime,size")
        var items: [RemoteItem] = []
        while let url = next {
            let (data, _) = try await oauth.send(HTTP.request(url))
            let page = try HTTP.decode(Page.self, from: data)
            items += page.value.map(\.item)
            next = page.nextLink.flatMap(URL.init(string:))
        }
        return items
    }

    func createFolder(named name: String, in folder: RemoteFolder) async throws -> RemoteFolder {
        let url = graph.appendingPathComponent("me/drive/items/\(folder.id)/children")
        let body: [String: Any] = ["name": name, "folder": [String: Any](), "@microsoft.graph.conflictBehavior": "rename"]
        let (data, _) = try await oauth.send(HTTP.request(url, method: "POST", json: body))
        return folder.child(try HTTP.decode(DriveItem.self, from: data).item)
    }

    func upload(_ data: Data, named name: String, to folder: RemoteFolder, replacing existing: RemoteItem?) async throws -> RemoteItem {
        let target = "\(graph.absoluteString)/me/drive/items/\(folder.id):/\(name.urlPathSegmentEncoded):"
        // Small files go up in one request; bigger ones (PDF notebooks) use an upload session.
        if data.count < 4 * 1024 * 1024 {
            var request = HTTP.request(URL(string: "\(target)/content")!, method: "PUT")
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            request.httpBody = data
            let (response, _) = try await oauth.send(request)
            return try HTTP.decode(DriveItem.self, from: response).item
        }

        struct Session: Decodable { let uploadUrl: String }
        let body: [String: Any] = ["item": ["@microsoft.graph.conflictBehavior": "replace"]]
        let (sessionData, _) = try await oauth.send(HTTP.request(URL(string: "\(target)/createUploadSession")!, method: "POST", json: body))
        guard let uploadURL = URL(string: try HTTP.decode(Session.self, from: sessionData).uploadUrl) else {
            throw ParchmentError.sync("OneDrive didn't accept the upload.")
        }
        let chunk = 320 * 1024 * 16 // must be a multiple of 320 KiB
        var offset = 0
        var last = Data()
        while offset < data.count {
            let end = min(offset + chunk, data.count)
            var request = URLRequest(url: uploadURL) // pre-authorized: no bearer token
            request.httpMethod = "PUT"
            request.setValue("bytes \(offset)-\(end - 1)/\(data.count)", forHTTPHeaderField: "Content-Range")
            request.httpBody = data.subdata(in: offset..<end)
            last = try await HTTP.send(request).0
            offset = end
        }
        return try HTTP.decode(DriveItem.self, from: last).item
    }

    func download(_ item: RemoteItem) async throws -> Data {
        try await oauth.send(HTTP.request(graph.appendingPathComponent("me/drive/items/\(item.id)/content"))).0
    }
}
