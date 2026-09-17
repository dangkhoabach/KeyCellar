/// Headless domain + data layer for DKB Secret: models, GRDB storage, the
/// Secure Enclave / HPKE sealing code and the vault service. No SwiftUI or
/// AppKit here, so `swift test` runs it without the app.
public enum DKBSecretCore {
    public static let version = "1.0.0"
}
