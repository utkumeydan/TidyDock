import Foundation
import Sparkle

/// Wraps Sparkle. Updates stay off until the build has a real feed URL and
/// EdDSA public key, so local and unconfigured builds never error.
final class Updater {
    private let controller: SPUStandardUpdaterController?

    init() {
        let info = Bundle.main.infoDictionary ?? [:]
        let key = info["SUPublicEDKey"] as? String ?? ""
        let feed = info["SUFeedURL"] as? String ?? ""
        let configured = !key.isEmpty && !key.hasPrefix("REPLACE") && !feed.isEmpty
        controller = configured
            ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            : nil
        if !configured {
            log.notice("Sparkle is not configured in Info.plist; automatic updates are off")
        }
    }

    var isAvailable: Bool { controller != nil }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
