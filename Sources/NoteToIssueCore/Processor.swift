import Foundation

public actor Processor {
    public private(set) var entries: [String: Entry]
    private let journal: StateStoring
    private let analyzer: Analyzing
    private let github: GitHubServing
    private var busy = false

    public init(journal: StateStoring, analyzer: Analyzing = OpenRouterClient(), github: GitHubServing = GitHubClient()) throws {
        self.journal = journal; self.analyzer = analyzer; self.github = github
        var entries = try journal.load()
        var recovered = false
        for (id, var entry) in entries where entry.status == .publishing {
            entry.status = .uncertain
            entry.message = "L'app s'est arrêtée pendant la publication. Vérifie GitHub avant toute nouvelle tentative."
            entries[id] = entry; recovered = true
        }
        if recovered { try journal.save(entries) }
        self.entries = entries
    }

    public var known: [String: Double] {
        entries.mapValues { entry in
            [.published, .publishing, .uncertain].contains(entry.status) ? -1 : entry.note.modifiedAt
        }
    }

    private func begin() throws {
        guard !busy else { throw AppError.message("Un traitement est déjà en cours.") }
        busy = true
    }
    private func persist(_ entry: Entry) throws {
        var next = entries
        next[entry.id] = entry
        try journal.save(next) // Commit to memory only after the durable write succeeds.
        entries = next
    }

    @discardableResult
    public func process(note: Note, settings: Settings, key: String, now: Date = Date(), force: Bool = false) async throws -> Entry? {
        try begin(); defer { busy = false }
        try settings.validate()
        guard note.modifiedAt.isFinite, now.timeIntervalSince1970 - note.modifiedAt >= 30 else { return nil }
        if let existing = entries[note.id] {
            if [.published, .publishing, .uncertain].contains(existing.status) { return existing }
            if !force && existing.note.fingerprint == note.fingerprint { return existing }
        }
        var entry = Entry(note: note, repository: settings.defaultRepository, status: .review)
        do {
            entry.repository = try Routing.repository(for: note.text, defaultRepository: settings.defaultRepository)
            guard note.text.count <= 24_000 else { throw AppError.message("Note trop longue (24 000 caractères maximum).") }
            if note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                entry.status = .ignored; entry.message = "Note vide."
            } else {
                let labels = try await github.labels(repository: entry.repository)
                let draft = try await analyzer.analyze(note: note, repository: entry.repository, labels: labels, settings: settings, key: key)
                    .validated(availableLabels: labels)
                entry.draft = draft
                entry.status = draft.isIssue ? .review : .ignored
                entry.message = draft.reason
            }
        } catch {
            entry.status = .failed
            entry.message = Self.safeMessage(error)
        }
        entry.updatedAt = now
        try persist(entry)
        if entry.status == .review, settings.automatic, (entry.draft?.confidence ?? 0) >= 0.90 {
            return try await publish(entry)
        }
        return entry
    }

    public func publishReviewed(id: String) async throws -> Entry {
        try begin(); defer { busy = false }
        guard let entry = entries[id], entry.status == .review, entry.draft?.isIssue == true else {
            throw AppError.message("Seule une proposition en attente peut être publiée.")
        }
        return try await publish(entry)
    }

    private func publish(_ original: Entry) async throws -> Entry {
        var entry = original
        do {
            let labels = try await github.labels(repository: entry.repository)
            guard let draft = entry.draft else { throw AppError.message("Proposition absente.") }
            _ = try draft.validated(availableLabels: labels)
            if let existing = try await github.find(repository: entry.repository, marker: entry.note.marker) {
                entry.status = .published; entry.issueURL = existing
                entry.message = "Issue existante retrouvée."
                try persist(entry)
                return entry
            }
        } catch {
            entry.status = .failed; entry.message = Self.safeMessage(error)
            try persist(entry)
            return entry
        }
        entry.status = .publishing
        entry.message = "Envoi à GitHub."
        try persist(entry) // Required before any irreversible external side effect.
        let url: URL
        do {
            url = try await github.create(repository: entry.repository, draft: entry.draft!, marker: entry.note.marker)
        } catch {
            entry.status = .uncertain
            entry.message = "Le résultat de l'envoi est inconnu. Utilise Vérifier GitHub ; aucune nouvelle publication automatique."
            try persist(entry)
            return entry
        }
        entry.status = .published; entry.issueURL = url; entry.message = "Issue créée avec ses labels."
        entry.updatedAt = Date()
        try persist(entry)
        return entry
    }

    public func reconcile(id: String) async throws -> Entry {
        try begin(); defer { busy = false }
        guard var entry = entries[id], [.uncertain, .publishing].contains(entry.status) else {
            throw AppError.message("Aucune publication incertaine à vérifier.")
        }
        if let url = try await github.find(repository: entry.repository, marker: entry.note.marker) {
            entry.status = .published; entry.issueURL = url; entry.message = "Issue retrouvée sur GitHub."
        } else {
            entry.message = "Aucune issue retrouvée pour le moment. La note reste bloquée pour éviter un doublon."
        }
        try persist(entry)
        return entry
    }

    private static func safeMessage(_ error: Error) -> String {
        // Do not persist response bodies, process output, authentication details or raw URLs.
        if let error = error as? AppError { return error.localizedDescription }
        return "Service indisponible ou données invalides. Vérifie la connexion et réessaie manuellement."
    }
}
