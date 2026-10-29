import Foundation
import CryptoKit

public enum AppError: LocalizedError {
    case message(String)
    public var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

public struct Note: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let text: String
    public let modifiedAt: Double
    public let folder: String

    public init(id: String, title: String, text: String, modifiedAt: Double, folder: String = "") {
        self.id = id; self.title = title; self.text = text
        self.modifiedAt = modifiedAt; self.folder = folder
    }
    public var fingerprint: String { Self.hash(title + "\u{0}" + text) }
    public var marker: String { "<!-- note-to-issue:" + Self.hash(id) + " -->" }
    private static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

public struct Draft: Codable, Equatable, Sendable {
    public let isIssue: Bool
    public let confidence: Double
    public let reason: String
    public let title: String
    public let body: String
    public let labels: [String]

    public init(isIssue: Bool, confidence: Double, reason: String, title: String, body: String, labels: [String]) {
        self.isIssue = isIssue; self.confidence = confidence; self.reason = reason
        self.title = title; self.body = body; self.labels = labels
    }

    public func validated(availableLabels: [String]) throws -> Draft {
        guard confidence.isFinite, (0...1).contains(confidence), !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              reason.count <= 2000, labels.count <= 10,
              Set(labels).isSubset(of: Set(availableLabels)), Set(labels).count == labels.count else {
            throw AppError.message("Réponse IA invalide : confiance ou labels non valides.")
        }
        if isIssue {
            guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 256,
                  !title.contains("\n"), !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  body.count <= 55_000, !body.contains("<!-- note-to-issue:") else {
                throw AppError.message("Réponse IA invalide : titre ou description non valide.")
            }
        }
        return self
    }
}

public struct Settings: Codable, Equatable, Sendable {
    public var account = "iCloud"
    public var folder = ""
    public var defaultRepository = "kroco-edu/app"
    public var model = "openai/gpt-4.1-mini"
    public var automatic = true
    public var interval: Double = 60
    public var launchAtLogin = true
    public var monitoringEnabled = true
    public init() {}
    public func validate() throws {
        _ = try Routing.validate(defaultRepository)
        guard !account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              interval.isFinite, interval >= 60, interval <= 86_400 else {
            throw AppError.message("Vérifie le compte Notes, le modèle et l'intervalle (60 à 86 400 s).")
        }
    }
}

public enum EntryStatus: String, Codable, Sendable {
    case ignored, review, published, publishing, uncertain, failed
    public var label: String {
        switch self {
        case .ignored: return "Ignorée"
        case .review: return "À vérifier"
        case .published: return "Publiée"
        case .publishing: return "Publication en cours"
        case .uncertain: return "Publication à vérifier"
        case .failed: return "Erreur"
        }
    }
}

public struct Entry: Codable, Equatable, Identifiable, Sendable {
    public var note: Note
    public var repository: String
    public var status: EntryStatus
    public var draft: Draft?
    public var issueURL: URL?
    public var message: String
    public var updatedAt: Date
    public var id: String { note.id }
    public init(note: Note, repository: String, status: EntryStatus, draft: Draft? = nil,
                issueURL: URL? = nil, message: String = "", updatedAt: Date = Date()) {
        self.note = note; self.repository = repository; self.status = status
        self.draft = draft; self.issueURL = issueURL; self.message = message; self.updatedAt = updatedAt
    }
}
