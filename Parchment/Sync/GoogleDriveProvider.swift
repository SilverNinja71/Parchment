import Foundation

private let googleFolderType = "application/vnd.google-apps.folder"

/// Google Drive through the Drive v3 REST API.
@MainActor
final class GoogleDriveProvider: OAuthCloudProvider {
    let service = CloudService.googleDrive
    let oauth: OAuthClient
    private let api = "https://www.googleapis.com/drive/v3"
    private let uploadAPI = "https://www.googleapis.com/upload/drive/v3"
    private static let fields = "id,name,mimeType,modifiedTime,size"

    init() {
        // An iOS client ID "123-abc.apps.googleusercontent.com" redirects to
        // "com.googleusercontent.apps.123-abc:/oauth2redirect".
        let clientID = CloudCredentials.googleClientID
        let scheme = clientID.components(separatedBy: ".").reversed().joined(separator: ".")
        oauth = OAuthClient(configuration: OAuthConfiguration(
            name: "google",
            authorizeURL: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
            tokenURL: URL(string: "https://oauth2.googleapis.com/token")!,
            clientID: clientID,
            redirectURI: "\(scheme):/oauth2redirect",
            callbackScheme: scheme,
            // Full Drive access so you can choose any folder (see README.md about Google's review).
            scopes: ["https://www.googleapis.com/auth/drive"],
            extraParameters: ["prompt": "select_account"]))
    }

    private struct File: Decodable {
        let id: String
        let name: String
        let mimeType: String?
        let modifiedTime: String?
        let size: String?

        var item: RemoteItem {
            RemoteItem(id: id, name: name, isFolder: mimeType == googleFolderType,
                       modified: CloudDate.parse(modifiedTime), size: size.flatMap { Int($0) })
        }
    }

    func accountName() async throws -> String {
        struct About: Decodable {
            struct User: Decodable { let displayName: String?; let emailAddress: String? }
            let user: User
        }
        let (data, _) = try await oauth.send(HTTP.request(URL(string: "\(api)/about?fields=user(displayName,emailAddress)")!))
        let about = try HTTP.decode(About.self, from: data)
        return about.user.emailAddress ?? about.user.displayName ?? "Google account"
    }

    func rootFolder() -> RemoteFolder {
        RemoteFolder(id: "root", name: "My Drive", displayPath: "My Drive")
    }

    func list(_ folder: RemoteFolder) async throws -> [RemoteItem] {
        struct Page: Decodable { let files: [File]; let nextPageToken: String? }
        var items: [RemoteItem] = []
        var pageToken: String?
        repeat {
            var components = URLComponents(string: "\(api)/files")!
            components.queryItems = [
                URLQueryItem(name: "q", value: "'\(folder.id)' in parents and trashed = false"),
                URLQueryItem(name: "fields", value: "nextPageToken,files(\(Self.fields))"),
                URLQueryItem(name: "pageSize", value: "200"),
                URLQueryItem(name: "orderBy", value: "folder,name"),
            ]
            if let pageToken { components.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            let (data, _) = try await oauth.send(HTTP.request(components.url!))
            let page = try HTTP.decode(Page.self, from: data)
            items += page.files.map(\.item)
            pageToken = page.nextPageToken
        } while pageToken != nil
        return items
    }

    func createFolder(named name: String, in folder: RemoteFolder) async throws -> RemoteFolder {
        let body: [String: Any] = ["name": name, "mimeType": googleFolderType, "parents": [folder.id]]
        let (data, _) = try await oauth.send(HTTP.request(URL(string: "\(api)/files?fields=\(Self.fields)")!, method: "POST", json: body))
        return folder.child(try HTTP.decode(File.self, from: data).item)
    }

    func upload(_ data: Data, named name: String, to folder: RemoteFolder, replacing existing: RemoteItem?) async throws -> RemoteItem {
        // Google Drive allows duplicate names, so existing files are always updated by ID.
        var request: URLRequest
        if let existing {
            request = HTTP.request(URL(string: "\(uploadAPI)/files/\(existing.id)?uploadType=resumable&fields=\(Self.fields)")!,
                                   method: "PATCH", json: ["name": name])
        } else {
            request = HTTP.request(URL(string: "\(uploadAPI)/files?uploadType=resumable&fields=\(Self.fields)")!,
                                   method: "POST", json: ["name": name, "parents": [folder.id]])
        }
        request.setValue("application/octet-stream", forHTTPHeaderField: "X-Upload-Content-Type")
        request.setValue("\(data.count)", forHTTPHeaderField: "X-Upload-Content-Length")
        let (_, response) = try await oauth.send(request)
        guard let location = response.value(forHTTPHeaderField: "Location"), let sessionURL = URL(string: location) else {
            throw ParchmentError.sync("Google Drive didn't accept the upload.")
        }

        var put = URLRequest(url: sessionURL)
        put.httpMethod = "PUT"
        put.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        put.httpBody = data
        let (result, _) = try await oauth.send(put)
        return try HTTP.decode(File.self, from: result).item
    }

    func download(_ item: RemoteItem) async throws -> Data {
        try await oauth.send(HTTP.request(URL(string: "\(api)/files/\(item.id)?alt=media")!)).0
    }
}
