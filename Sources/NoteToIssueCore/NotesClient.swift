import Foundation

public protocol NotesReading {
    func read(settings: Settings, known: [String: Double]) async throws -> [Note]
    func readOne(id: String, settings: Settings) async throws -> Note
}
public struct NotesClient: NotesReading {
    private let runner: CommandRunning
    public init(runner: CommandRunning = ProcessRunner()) { self.runner = runner }
    public func read(settings: Settings, known: [String: Double]) async throws -> [Note] {
        try await read(settings: settings, known: known, onlyID: nil)
    }
    public func readOne(id: String, settings: Settings) async throws -> Note {
        guard let note = try await read(settings: settings, known: [:], onlyID: id).first, note.id == id else {
            throw AppError.message("Note inaccessible : supprimée, verrouillée, déplacée ou encore en cours d'édition. Réessaie après 30 secondes.")
        }
        return note
    }
    private func read(settings: Settings, known: [String: Double], onlyID: String?) async throws -> [Note] {
        try settings.validate()
        let packaged = Bundle.main.resourceURL?.appendingPathComponent("Notes/ReadNotes.js")
        let scriptURL = packaged.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
            ?? Bundle.module.url(forResource: "ReadNotes", withExtension: "js", subdirectory: "Resources")
        guard let script = scriptURL else {
            throw AppError.message("Script Notes absent du bundle. Reconstruis l'application.")
        }
        var payload: [String: Any] = ["account": settings.account, "folder": settings.folder, "known": known, "limit": 10]
        if let onlyID { payload["onlyID"] = onlyID }
        let config = try JSONSerialization.data(withJSONObject: payload)
        let data = try await runner.run(executable: "/usr/bin/osascript", arguments: ["-l", "JavaScript", script.path, String(decoding: config, as: UTF8.self)], input: nil, timeout: 60)
        return try JSONDecoder().decode([Note].self, from: data)
    }
}
