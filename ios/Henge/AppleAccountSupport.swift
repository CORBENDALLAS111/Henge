import Foundation

/// Compatibility is a device/kernel configuration, never evidence of account sign-in.
enum AppleAccountSupport {
    static let recommendedBuild = "24G90"
    static let supportedBuilds: Set<String> = ["22G120", "24G90", "25G83", "26B123"]
    static let setupRequestedKey = "henge.appleAccount.setupRequested"
    static let setupRequested = Notification.Name("henge.appleAccount.setupRequested")
    static func supports(build: String) -> Bool { supportedBuilds.contains(build) }
    static func status(identityPresent: Bool, nativeStatus: Int32?) -> String {
        guard identityPresent else { return "Not enabled for this Mac" }
        switch nativeStatus {
        case 2: return "Compatibility active"
        case -1: return "Compatibility could not start"
        case 0, 1: return "Waiting for a supported Mac to start"
        case nil: return "Identity profile saved"
        default: return "Compatibility status unavailable"
        }
    }
    @MainActor static func requestSetup() {
        UserDefaults.standard.set(true, forKey: setupRequestedKey)
        NotificationCenter.default.post(name: setupRequested, object: nil)
    }
}
