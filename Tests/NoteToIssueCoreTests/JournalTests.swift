import XCTest
@testable import NoteToIssueCore

final class JournalTests: XCTestCase {
    var directory: URL!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: directory) }

    func testRoundTripAndPrivatePermissions() throws {
        let journal = try Journal(directory: directory)
        let note = Note(id: "one", title: "Test", text: "private", modifiedAt: 1)
        let entry = Entry(note: note, repository: "kroco-edu/app", status: .ignored)
        try journal.save([note.id: entry])
        XCTAssertEqual(try journal.load()["one"]?.note.text, "private")
        let permissions = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("state.json").path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600)
    }

    func testCorruptStateFailsClosed() throws {
        let journal = try Journal(directory: directory)
        try Data("not json".utf8).write(to: directory.appendingPathComponent("state.json"))
        XCTAssertThrowsError(try journal.load())
    }

    func testSecondInstanceCannotAcquireLock() throws {
        let first = try InstanceLock(directory: directory)
        try withExtendedLifetime(first) {
            XCTAssertThrowsError(try InstanceLock(directory: directory))
        }
    }

    func testMissingJournalStartsEmpty() throws {
        XCTAssertTrue(try Journal(directory: directory).load().isEmpty)
    }
}
