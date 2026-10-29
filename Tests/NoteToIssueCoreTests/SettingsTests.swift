import XCTest
@testable import NoteToIssueCore

final class SettingsTests: XCTestCase {
    func testDefaultsAreLightweightAutomaticAndResumeAtLogin() throws {
        let settings = Settings()
        XCTAssertEqual(settings.interval, 60)
        XCTAssertEqual(settings.defaultRepository, "kroco-edu/app")
        XCTAssertEqual(settings.model, "openrouter/free")
        XCTAssertTrue(settings.automatic)
        XCTAssertTrue(settings.launchAtLogin)
        XCTAssertTrue(settings.monitoringEnabled)
        XCTAssertNoThrow(try settings.validate())
    }
    func testInvalidScheduleRejected() {
        for interval in [0.0, 59, Double.nan, Double.infinity, 86_401] {
            var settings = Settings(); settings.interval = interval
            XCTAssertThrowsError(try settings.validate())
        }
    }
    func testSavedPauseSurvivesRelaunch() throws {
        let suite = "NoteToIssueTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        var settings = Settings(); settings.monitoringEnabled = false; settings.interval = 300
        try store.save(settings)
        let loaded = try SettingsStore(defaults: defaults).load()
        XCTAssertFalse(loaded.monitoringEnabled)
        XCTAssertEqual(loaded.interval, 300)
    }
}
