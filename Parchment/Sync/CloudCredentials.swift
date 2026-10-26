import Foundation

/// Paste your own app IDs here (see README.md for step-by-step instructions).
///
/// These are *public* client IDs used with PKCE, so they are safe to ship in the app.
/// No client secrets are needed and none should ever go in this file.
enum CloudCredentials {
    /// Microsoft Entra (Azure) app registration → "Application (client) ID".
    static let oneDriveClientID = "YOUR_MICROSOFT_CLIENT_ID"

    /// Google Cloud Console → Credentials → OAuth client ID of type **iOS**.
    /// Looks like `1234567890-abc123.apps.googleusercontent.com`.
    static let googleClientID = "YOUR_GOOGLE_IOS_CLIENT_ID.apps.googleusercontent.com"

    /// Dropbox App Console → your app → "App key".
    static let dropboxAppKey = "YOUR_DROPBOX_APP_KEY"

    static func isConfigured(_ value: String) -> Bool {
        !value.isEmpty && !value.contains("YOUR_")
    }
}
