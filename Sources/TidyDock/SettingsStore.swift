import Foundation
import TidyDockCore

/// Loads and saves `TidySettings` in UserDefaults and tells observers when they change.
final class SettingsStore {
    static let didChange = Notification.Name("TidyDockSettingsDidChange")

    private let defaults: UserDefaults
    private let key = "settings.v1"

    private(set) var settings: TidySettings

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let saved = try? JSONDecoder().decode(TidySettings.self, from: data) {
            settings = saved
        } else {
            settings = .default
        }
    }

    func update(_ change: (inout TidySettings) -> Void) {
        var copy = settings
        change(&copy)
        guard copy != settings else { return }
        settings = copy
        if let data = try? JSONEncoder().encode(copy) {
            defaults.set(data, forKey: key)
        }
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}

/// Session-only state that is deliberately not saved.
final class SessionState {
    static let didChange = Notification.Name("TidyDockSessionDidChange")

    var isPaused = false {
        didSet {
            guard isPaused != oldValue else { return }
            NotificationCenter.default.post(name: Self.didChange, object: self)
        }
    }
}
