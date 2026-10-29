import XCTest
@testable import NoteToIssueCore

final class RoutingTests: XCTestCase {
    func testDefaultAndReferencesDoNotReroute() throws {
        XCTAssertEqual(try Routing.repository(for: "Corriger le login, voir other/project", defaultRepository: "kroco-edu/app"), "kroco-edu/app")
    }

    func testExplicitDestinations() throws {
        for text in ["repo: remimenguy/test", "Repository: remimenguy/test", "dépôt : remimenguy/test", "Crée l'issue dans le repo remimenguy/test", "create issue in remimenguy/test", "repo: https://github.com/remimenguy/test"] {
            XCTAssertEqual(try Routing.repository(for: text, defaultRepository: "kroco-edu/app"), "remimenguy/test", text)
        }
    }

    func testConflictingAndMalformedDirectivesAreRejected() {
        for text in ["repo: a/one\nrepo: b/two", "repo: bad", "repo: owner/repo/extra", "repo: https://evil.test/a/b", "repo:"] {
            XCTAssertThrowsError(try Routing.repository(for: text, defaultRepository: "kroco-edu/app"), text)
        }
    }

    func testInvalidDefaultRejected() {
        XCTAssertThrowsError(try Routing.repository(for: "bug", defaultRepository: "../x"))
    }

    func testStableMarkerAndContentFingerprint() {
        let note = Note(id: "secret-id", title: "Bug", text: "Le bouton plante", modifiedAt: 10)
        let edited = Note(id: "secret-id", title: "Bug", text: "Le bouton plante encore", modifiedAt: 20)
        XCTAssertEqual(note.marker, edited.marker)
        XCTAssertFalse(note.marker.contains("secret-id"))
        XCTAssertNotEqual(note.fingerprint, edited.fingerprint)
    }

    func testDraftValidationRejectsBadConfidenceAndUnknownLabels() {
        for confidence in [-0.1, 1.1, Double.nan, Double.infinity] {
            let draft = Draft(isIssue: true, confidence: confidence, reason: "Bug", title: "Corriger", body: "Détail", labels: ["bug"])
            XCTAssertThrowsError(try draft.validated(availableLabels: ["bug"]))
        }
        let draft = Draft(isIssue: true, confidence: 0.95, reason: "Bug", title: "Corriger", body: "Détail", labels: ["invented"])
        XCTAssertThrowsError(try draft.validated(availableLabels: ["bug"]))
    }
}
