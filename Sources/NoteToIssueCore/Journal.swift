import Foundation
import Darwin

public protocol StateStoring {
    func load() throws -> [String: Entry]
    func save(_ entries: [String: Entry]) throws
}

public final class Journal: StateStoring {
    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NoteToIssue", isDirectory: true)
    }
    private let directory: URL
    private var file: URL { directory.appendingPathComponent("state.json") }
    private struct Envelope: Codable { let version: Int; let entries: [String: Entry] }

    public init(directory: URL = Journal.defaultDirectory) throws {
        self.directory = directory
        try Self.secureDirectory(directory)
    }
    static func secureDirectory(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }
    public func load() throws -> [String: Entry] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [:] }
        do {
            let envelope = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: file))
            guard envelope.version == 1 else { throw AppError.message("Version du journal inconnue.") }
            return envelope.entries
        } catch {
            throw AppError.message("Journal local illisible. Aucun envoi autorisé. Conserve state.json avant de le réparer.")
        }
    }
    public func save(_ entries: [String: Entry]) throws {
        let data = try JSONEncoder().encode(Envelope(version: 1, entries: entries))
        let temporary = directory.appendingPathComponent(".state-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw AppError.message("Impossible d'écrire le journal local.")
        }
        defer { try? FileManager.default.removeItem(at: temporary) }
        let handle = try FileHandle(forWritingTo: temporary)
        do { try handle.write(contentsOf: data); try handle.synchronize(); try handle.close() }
        catch { try? handle.close(); throw error }
        guard rename(temporary.path, file.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let descriptor = open(directory.path, O_RDONLY)
        if descriptor >= 0 { _ = fsync(descriptor); close(descriptor) }
    }
}

public final class InstanceLock {
    private let descriptor: Int32
    public init(directory: URL = Journal.defaultDirectory) throws {
        try Journal.secureDirectory(directory)
        descriptor = open(directory.appendingPathComponent("instance.lock").path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw AppError.message("Impossible d'ouvrir le verrou local.") }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw AppError.message("Note to Issue est déjà ouverte. Utilise l'instance existante.")
        }
    }
    deinit { flock(descriptor, LOCK_UN); close(descriptor) }
}
