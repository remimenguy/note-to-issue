import XCTest
@testable import NoteToIssueCore

final class AnalysisStub: Analyzing {
    var calls = 0
    var failure: Error?
    var result = Draft(isIssue: true, confidence: 0.98, reason: "Action concrète", title: "Corriger le bouton", body: "Le bouton plante.", labels: ["bug"])
    func analyze(note: Note, repository: String, labels: [String], settings: Settings, key: String) async throws -> Draft {
        calls += 1
        if let failure { throw failure }
        return result
    }
}
final class GitHubStub: GitHubServing {
    var created: [(String, Draft, String)] = []
    var found: URL?
    var failCreate = false
    var beforeCreate: (() throws -> Void)?
    func labels(repository: String) async throws -> [String] { ["bug", "enhancement"] }
    func find(repository: String, marker: String) async throws -> URL? { found }
    func create(repository: String, draft: Draft, marker: String) async throws -> URL {
        try beforeCreate?()
        created.append((repository, draft, marker))
        if failCreate { throw AppError.message("Lost response") }
        return URL(string: "https://github.com/\(repository)/issues/1")!
    }
}

final class ProcessorTests: XCTestCase {
    var directory: URL!
    var journal: Journal!
    var analyzer: AnalysisStub!
    var github: GitHubStub!
    var processor: Processor!
    let note = Note(id: "one", title: "Bug", text: "Le bouton plante", modifiedAt: 100)
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        journal = try Journal(directory: directory)
        analyzer = AnalysisStub(); github = GitHubStub()
        processor = try Processor(journal: journal, analyzer: analyzer, github: github)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: directory) }

    func testAutomaticPublicationPersistsIntentBeforePOST() async throws {
        github.beforeCreate = { XCTAssertEqual(try self.journal.load()["one"]?.status, .publishing) }
        let entry = try await processor.process(note: note, settings: Settings(), key: "test", now: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(entry?.status, .published)
        XCTAssertEqual(github.created.first?.0, "kroco-edu/app")
        XCTAssertEqual(try journal.load()["one"]?.issueURL?.absoluteString, "https://github.com/kroco-edu/app/issues/1")
    }

    func testPublishedNoteNeverCreatesAgainEvenWhenEdited() async throws {
        _ = try await processor.process(note: note, settings: Settings(), key: "test", now: Date(timeIntervalSince1970: 200))
        let edited = Note(id: "one", title: "Edited", text: "repo: other/repo\nAutre bug", modifiedAt: 200)
        _ = try await processor.process(note: edited, settings: Settings(), key: "test", now: Date(timeIntervalSince1970: 300))
        XCTAssertEqual(github.created.count, 1)
        XCTAssertEqual(analyzer.calls, 1)
    }

    func testNonIssueCachedUntilContentChanges() async throws {
        analyzer.result = Draft(isIssue: false, confidence: 0.99, reason: "Courses", title: "", body: "", labels: [])
        for _ in 0..<2 { _ = try await processor.process(note: note, settings: Settings(), key: "test", now: Date(timeIntervalSince1970: 200)) }
        XCTAssertEqual(analyzer.calls, 1)
        XCTAssertTrue(github.created.isEmpty)
        let changed = Note(id: "one", title: "Bug", text: "texte modifié", modifiedAt: 200)
        _ = try await processor.process(note: changed, settings: Settings(), key: "test", now: Date(timeIntervalSince1970: 300))
        XCTAssertEqual(analyzer.calls, 2)
    }

    func testLowConfidenceAndPreviewModeDoNotPublish() async throws {
        analyzer.result = Draft(isIssue: true, confidence: 0.8, reason: "Ambigu", title: "Corriger", body: "Contexte", labels: [])
        let review = try await processor.process(note: note, settings: Settings(), key: "test", now: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(review?.status, .review)
        XCTAssertTrue(github.created.isEmpty)
        analyzer.result = Draft(isIssue: true, confidence: 0.99, reason: "Bug", title: "Corriger", body: "Contexte", labels: [])
        var settings = Settings(); settings.automatic = false
        let other = Note(id: "two", title: "Bug", text: "Autre bug", modifiedAt: 100)
        let preview = try await processor.process(note: other, settings: settings, key: "test", now: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(preview?.status, .review)
        XCTAssertTrue(github.created.isEmpty)
    }

    func testUncertainPublicationNeverRetriesAndCanRecover() async throws {
        github.failCreate = true
        let entry = try await processor.process(note: note, settings: Settings(), key: "test", now: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(entry?.status, .uncertain)
        _ = try await processor.process(note: note, settings: Settings(), key: "test", now: Date(timeIntervalSince1970: 300))
        XCTAssertEqual(github.created.count, 1)
        github.found = URL(string: "https://github.com/kroco-edu/app/issues/42")
        let recovered = try await processor.reconcile(id: "one")
        XCTAssertEqual(recovered.status, .published)
        XCTAssertEqual(github.created.count, 1)
    }

    func testExistingMarkerRecoversWithoutPOST() async throws {
        github.found = URL(string: "https://github.com/kroco-edu/app/issues/42")
        let entry = try await processor.process(note: note, settings: Settings(), key: "test", now: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(entry?.issueURL, github.found)
        XCTAssertTrue(github.created.isEmpty)
    }

    func testRecentAndOversizedNotesAvoidAI() async throws {
        let recent = try await processor.process(note: note, settings: Settings(), key: "test", now: Date(timeIntervalSince1970: 110))
        XCTAssertNil(recent)
        let huge = Note(id: "huge", title: "Huge", text: String(repeating: "x", count: 24_001), modifiedAt: 100)
        let entry = try await processor.process(note: huge, settings: Settings(), key: "test", now: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(entry?.status, .failed)
        XCTAssertEqual(analyzer.calls, 0)
    }

    func testCrashIntentLoadedAsUncertain() async throws {
        try journal.save(["one": Entry(note: note, repository: "kroco-edu/app", status: .publishing)])
        let reloaded = try Processor(journal: journal, analyzer: analyzer, github: github)
        let entries = await reloaded.entries
        XCTAssertEqual(entries["one"]?.status, .uncertain)
    }

    func testJournalFailurePreventsPOST() async throws {
        try FileManager.default.removeItem(at: directory)
        try Data().write(to: directory) // replace state directory with a file
        do {
            _ = try await processor.process(note: note, settings: Settings(), key: "test", now: Date(timeIntervalSince1970: 200))
            XCTFail("State failure swallowed")
        } catch {}
        XCTAssertTrue(github.created.isEmpty)
    }

    func testMetadataOnlyChangeAcknowledgedWithoutAnotherAnalysis() async throws {
        var settings = Settings(); settings.automatic = false
        _ = try await processor.process(note: note, settings: settings, key: "test", now: Date(timeIntervalSince1970: 200))
        let formatted = Note(id: note.id, title: note.title, text: note.text, modifiedAt: 200)
        _ = try await processor.process(note: formatted, settings: settings, key: "test", now: Date(timeIntervalSince1970: 300))
        let known = await processor.known
        XCTAssertEqual(known[note.id], -1)
        XCTAssertEqual(try journal.load()[note.id]?.note.modifiedAt, 200)
        XCTAssertEqual(analyzer.calls, 1)
    }

    func testPreviouslyProcessedNoteIsExcludedFromAutomaticReads() async throws {
        var settings = Settings(); settings.automatic = false
        _ = try await processor.process(note: note, settings: settings, key: "test", now: Date(timeIntervalSince1970: 200))
        let known = await processor.known
        XCTAssertEqual(known, ["one": -1])
    }

    func testDeferredAnalysisIsPersistedAndRetriedOnlyAfterDeadline() async throws {
        analyzer.failure = AnalysisDeferred(retryAt: Date(timeIntervalSince1970: 500), message: "Quota atteint.")
        let waiting = try await processor.process(note: note, settings: Settings(), key: "test", now: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(waiting?.status, .waiting)
        XCTAssertEqual(try journal.load()["one"]?.retryAt?.timeIntervalSince1970, 500)
        let early = await processor.knownNotes(at: Date(timeIntervalSince1970: 499))
        let ready = await processor.knownNotes(at: Date(timeIntervalSince1970: 500))
        XCTAssertEqual(early["one"], -1)
        XCTAssertNil(ready["one"])
        _ = try await processor.process(note: note, settings: Settings(), key: "test", now: Date(timeIntervalSince1970: 499), force: true)
        XCTAssertEqual(analyzer.calls, 1)
        analyzer.failure = nil
        let published = try await processor.process(note: note, settings: Settings(), key: "test", now: Date(timeIntervalSince1970: 501))
        XCTAssertEqual(published?.status, .published)
        XCTAssertEqual(analyzer.calls, 2)
        XCTAssertEqual(github.created.count, 1)
    }

    func testLegacy429FailuresBecomePendingWithoutResettingSuccessfulNotes() async throws {
        let old = Entry(note: note, repository: "kroco-edu/app", status: .failed, message: "OpenRouter HTTP 429. Vérifie la clé, le crédit et la compatibilité JSON Schema du modèle.")
        let other = Note(id: "done", title: "Done", text: "text", modifiedAt: 100)
        try journal.save(["one": old, "done": Entry(note: other, repository: "kroco-edu/app", status: .published)])
        let restarted = try Processor(journal: journal, analyzer: analyzer, github: github)
        let entries = await restarted.entries
        XCTAssertEqual(entries["one"]?.status, .waiting)
        XCTAssertEqual(entries["done"]?.status, .published)
        XCTAssertEqual(try journal.load()["one"]?.status, .waiting)
    }
    func testExplicitModelChangeReleasesOnlyUnfinishedNotes() async throws {
        analyzer.failure = AnalysisDeferred(retryAt: Date(timeIntervalSince1970: 500), message: "Quota gratuit.")
        _ = try await processor.process(note: note, settings: Settings(), key: "test", now: Date(timeIntervalSince1970: 200))
        var paid = Settings(); paid.model = "openai/gpt-4.1-mini"
        let known = await processor.knownNotes(at: Date(timeIntervalSince1970: 300), model: paid.model)
        XCTAssertNil(known["one"])
        analyzer.failure = nil
        let entry = try await processor.process(note: note, settings: paid, key: "test", now: Date(timeIntervalSince1970: 300))
        XCTAssertEqual(entry?.status, .published)
        XCTAssertEqual(github.created.count, 1)
    }
    func testCancellationDoesNotMarkANewNoteAsProcessed() async throws {
        analyzer.failure = CancellationError()
        do {
            _ = try await processor.process(note: note, settings: Settings(), key: "test", now: Date(timeIntervalSince1970: 200))
            XCTFail("Cancellation swallowed")
        } catch is CancellationError {}
        XCTAssertTrue(try journal.load().isEmpty)
        XCTAssertTrue(github.created.isEmpty)
    }
    func testReconnectionReschedulesOnlyUnfinishedWork() async throws {
        analyzer.failure = AnalysisDeferred(retryAt: Date(timeIntervalSince1970: 500), message: "Quota.")
        _ = try await processor.process(note: note, settings: Settings(), key: "test", now: Date(timeIntervalSince1970: 200))
        try await processor.rescheduleWaiting()
        let known = await processor.knownNotes(at: Date(timeIntervalSince1970: 300))
        XCTAssertNil(known["one"])
        XCTAssertEqual(try journal.load()["one"]?.status, .waiting)
        XCTAssertEqual(analyzer.calls, 1)
        XCTAssertTrue(github.created.isEmpty)
    }
}
