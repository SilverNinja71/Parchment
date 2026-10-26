import Foundation
import SwiftUI
import AuthenticationServices

/// Every place Parchment can sync to.
enum CloudService: String, CaseIterable, Identifiable, Codable {
    case iCloudDrive, oneDrive, googleDrive, dropbox, webDAV, otherApp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .iCloudDrive: return "iCloud Drive"
        case .oneDrive: return "OneDrive"
        case .googleDrive: return "Google Drive"
        case .dropbox: return "Dropbox"
        case .webDAV: return "WebDAV / Nextcloud"
        case .otherApp: return "Other Apps"
        }
    }

    var subtitle: String {
        switch self {
        case .iCloudDrive: return "Uses the Apple Account on this iPad"
        case .oneDrive: return "Sign in with your Microsoft account"
        case .googleDrive: return "Sign in with your Google account"
        case .dropbox: return "Sign in with your Dropbox account"
        case .webDAV: return "Nextcloud, ownCloud, Synology, Koofr, any WebDAV server"
        case .otherApp: return "Box, pCloud, Proton Drive, Synology Drive… via the Files app"
        }
    }

    var systemImage: String {
        switch self {
        case .iCloudDrive: return "icloud"
        case .oneDrive: return "cloud"
        case .googleDrive: return "triangle"
        case .dropbox: return "shippingbox"
        case .webDAV: return "server.rack"
        case .otherApp: return "folder"
        }
    }

    var tint: Color {
        switch self {
        case .iCloudDrive: return Color(red: 0.20, green: 0.55, blue: 0.95)
        case .oneDrive: return Color(red: 0.00, green: 0.47, blue: 0.83)
        case .googleDrive: return Color(red: 0.13, green: 0.59, blue: 0.33)
        case .dropbox: return Color(red: 0.00, green: 0.38, blue: 1.00)
        case .webDAV: return Color(red: 0.00, green: 0.51, blue: 0.79)
        case .otherApp: return .gray
        }
    }

    enum SignInStyle { case folderPicker, oauth, webDAVForm }

    var signInStyle: SignInStyle {
        switch self {
        case .iCloudDrive, .otherApp: return .folderPicker
        case .oneDrive, .googleDrive, .dropbox: return .oauth
        case .webDAV: return .webDAVForm
        }
    }
}

/// A folder in a cloud service. `id` is whatever the service needs to address it
/// (an item ID for OneDrive/Google Drive, a path for Dropbox/WebDAV/Files).
struct RemoteFolder: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    /// Human-readable location, e.g. "My Drive › School › Notes".
    var displayPath: String

    func child(_ item: RemoteItem) -> RemoteFolder {
        RemoteFolder(id: item.id, name: item.name, displayPath: displayPath + " › " + item.name)
    }
}

struct RemoteItem: Hashable, Identifiable {
    var id: String
    var name: String
    var isFolder: Bool
    var modified: Date?
    var size: Int?
}

/// What every sync destination implements.
@MainActor
protocol CloudProvider: AnyObject {
    var service: CloudService { get }
    var isSignedIn: Bool { get }
    func accountName() async throws -> String
    func rootFolder() -> RemoteFolder
    func list(_ folder: RemoteFolder) async throws -> [RemoteItem]
    func createFolder(named name: String, in folder: RemoteFolder) async throws -> RemoteFolder
    /// Uploads a file into `folder`, overwriting `existing` (or a file with the same name).
    func upload(_ data: Data, named name: String, to folder: RemoteFolder, replacing existing: RemoteItem?) async throws -> RemoteItem
    func download(_ item: RemoteItem) async throws -> Data
    func signOut()
}

/// Providers that sign in with OAuth in a web sheet.
@MainActor
protocol OAuthCloudProvider: CloudProvider {
    var oauth: OAuthClient { get }
}

extension OAuthCloudProvider {
    var isSignedIn: Bool { oauth.isSignedIn }
    func signOut() { oauth.signOut() }
    func signIn(using session: WebAuthenticationSession) async throws { try await oauth.signIn(using: session) }
}

extension String {
    /// Percent-encodes a single path segment (file or folder name).
    var urlPathSegmentEncoded: String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/:?#[]@!$&'()*+,;=")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}
