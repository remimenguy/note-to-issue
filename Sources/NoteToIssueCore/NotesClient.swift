import Foundation

public protocol NotesReading {
    func read(settings: Settings, known: [String: Double]) async throws -> [Note]
}
public struct NotesClient: NotesReading {
    private let runner: CommandRunning
    public init(runner: CommandRunning = ProcessRunner()) { self.runner = runner }
    public func read(settings: Settings, known: [String: Double]) async throws -> [Note] {
        try settings.validate()
        guard let script = Bundle.module.url(forResource: "ReadNotes", withExtension: "js", subdirectory: "Resources") else {
            throw AppError.message("Script Notes absent du bundle. Reconstruis l'application.")
        }
        let config = try JSONSerialization.data(withJSONObject: ["account": settings.account, "folder": settings.folder, "known": known, "limit": 10])
        let data = try await runner.run(executable: "/usr/bin/osascript", arguments: ["-l", "JavaScript", script.path, String(decoding: config, as: UTF8.self)], input: nil, timeout: 60)
        return try JSONDecoder().decode([Note].self, from: data)
    }
}
