import Foundation

public struct SettingsStore {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    public func load() throws -> Settings {
        guard let data = defaults.data(forKey: "settings") else { return Settings() }
        let settings = try JSONDecoder().decode(Settings.self, from: data)
        try settings.validate()
        return settings
    }
    public func save(_ settings: Settings) throws {
        try settings.validate()
        defaults.set(try JSONEncoder().encode(settings), forKey: "settings")
    }
}
