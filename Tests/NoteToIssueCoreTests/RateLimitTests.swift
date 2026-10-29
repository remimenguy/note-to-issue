import XCTest
@testable import NoteToIssueCore

final class VirtualAnalysisClock: AnalysisClock {
    var date = Date(timeIntervalSince1970: 1000)
    var sleeps: [Double] = []
    var cancelSleep = false
    func now() -> Date { date }
    func sleep(seconds: Double) async throws {
        try Task.checkCancellation()
        if cancelSleep { throw CancellationError() }
        sleeps.append(seconds); date.addTimeInterval(seconds)
    }
}

final class RateLimitTransport: HTTPTransport {
    let clock: VirtualAnalysisClock
    var remaining = 50
    var quotaChecks = 0
    var quotaStatus = 200
    var quotaRefreshDelay: Double = 0
    var postTimes: [Date] = []
    var responses: [(Int, [String: String], String)] = []
    init(clock: VirtualAnalysisClock) { self.clock = clock }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if request.url?.path == "/api/v1/key" {
            quotaChecks += 1
            if quotaChecks > 1 { clock.date.addTimeInterval(quotaRefreshDelay) }
            let data = Data("{\"data\":{\"free_model_daily_requests\":{\"remaining\":\(remaining)}}}".utf8)
            return (data, HTTPURLResponse(url: request.url!, statusCode: quotaStatus, httpVersion: nil, headerFields: nil)!)
        }
        postTimes.append(clock.now())
        let (status, headers, body) = responses.isEmpty ? (200, [:], "") : responses.removeFirst()
        let draft = #"{"isIssue":false,"confidence":0.99,"reason":"Note personnelle","title":"","body":"","labels":[]}"#
        let data = status == 200
            ? try JSONSerialization.data(withJSONObject: ["choices": [["finish_reason": "stop", "message": ["content": draft]]]])
            : Data(body.utf8)
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!)
    }
}

final class RateLimitTests: XCTestCase {
    let note = Note(id: "one", title: "Test", text: "Texte synthétique", modifiedAt: 1)
    func analyze(_ client: OpenRouterClient) async throws {
        _ = try await client.analyze(note: note, repository: "kroco-edu/app", labels: [], settings: Settings(), key: "test-key")
    }
    func testFreeRequestsArePacedAndQuotaCheckIsCached() async throws {
        let clock = VirtualAnalysisClock()
        let transport = RateLimitTransport(clock: clock)
        let client = OpenRouterClient(transport: transport, clock: clock)
        try await analyze(client); try await analyze(client)
        XCTAssertEqual(transport.postTimes.map(\.timeIntervalSince1970), [1000, 1005])
        XCTAssertEqual(clock.sleeps, [5])
        XCTAssertEqual(transport.quotaChecks, 1)
    }
    func testExhaustedDailyQuotaDoesNotSendInference() async throws {
        let clock = VirtualAnalysisClock(), transport = RateLimitTransport(clock: VirtualAnalysisClock())
        transport.remaining = 0
        let client = OpenRouterClient(transport: transport, clock: clock)
        do { try await analyze(client); XCTFail("Quota ignored") }
        catch let deferred as AnalysisDeferred { XCTAssertEqual(deferred.retryAt.timeIntervalSince1970, 86_405) }
        XCTAssertTrue(transport.postTimes.isEmpty)
    }
    func test429HonorsRetryAfterAndBlocksFurtherRequestsUntilReady() async throws {
        let clock = VirtualAnalysisClock(), transport = RateLimitTransport(clock: VirtualAnalysisClock())
        transport.responses = [(429, ["Retry-After": "120"], "")]
        let client = OpenRouterClient(transport: transport, clock: clock)
        for _ in 0..<2 {
            do { try await analyze(client); XCTFail("Rate limit ignored") }
            catch let deferred as AnalysisDeferred { XCTAssertEqual(deferred.retryAt.timeIntervalSince1970, 1120) }
        }
        XCTAssertEqual(transport.postTimes.count, 1)
        clock.date = Date(timeIntervalSince1970: 1121)
        try await analyze(client)
        XCTAssertEqual(transport.postTimes.count, 2)
    }
    func testRepeated429UsesExponentialBackoff() async throws {
        let clock = VirtualAnalysisClock(), transport = RateLimitTransport(clock: VirtualAnalysisClock())
        transport.responses = [(429, [:], ""), (429, [:], "")]
        let client = OpenRouterClient(transport: transport, clock: clock)
        do { try await analyze(client); XCTFail("Rate limit ignored") }
        catch let deferred as AnalysisDeferred { XCTAssertEqual(deferred.retryAt.timeIntervalSince1970, 1060) }
        clock.date = Date(timeIntervalSince1970: 1061)
        do { try await analyze(client); XCTFail("Rate limit ignored") }
        catch let deferred as AnalysisDeferred { XCTAssertEqual(deferred.retryAt.timeIntervalSince1970, 1181) }
    }
    func testResetHeaderAndDailyErrorAreRespected() async throws {
        for (headers, body, expected) in [
            (["X-RateLimit-Reset": "1300000"], "", 1300000.0),
            (["Retry-After": "60"], #"{"error":{"message":"Rate limit exceeded: free-models-per-day."}}"#, 86405.0),
            (["Retry-After": "Thu, 01 Jan 1970 00:30:00 GMT"], "", 1800.0)
        ] {
            let clock = VirtualAnalysisClock(), transport = RateLimitTransport(clock: VirtualAnalysisClock())
            transport.responses = [(429, headers, body)]
            let client = OpenRouterClient(transport: transport, clock: clock)
            do { try await analyze(client); XCTFail("Rate limit ignored") }
            catch let deferred as AnalysisDeferred { XCTAssertEqual(deferred.retryAt.timeIntervalSince1970, expected) }
        }
    }
    func testBadRequestIsNotAnAutomaticRetryAndDoesNotLeakBody() async throws {
        let clock = VirtualAnalysisClock(), transport = RateLimitTransport(clock: VirtualAnalysisClock())
        transport.responses = [(400, [:], #"{"error":{"message":"secret note text"}}"#)]
        let client = OpenRouterClient(transport: transport, clock: clock)
        do { try await analyze(client); XCTFail("Bad request accepted") }
        catch {
            XCTAssertFalse(error is AnalysisDeferred)
            XCTAssertFalse(error.localizedDescription.contains("secret note text"))
            XCTAssertTrue(error.localizedDescription.contains("400"))
        }
        XCTAssertEqual(transport.postTimes.count, 1)
    }
    func testStaleZeroQuotaDoesNotBlockAnotherDayWhenMetadataIsUnavailable() async throws {
        let clock = VirtualAnalysisClock()
        let transport = RateLimitTransport(clock: clock)
        transport.remaining = 0
        let client = OpenRouterClient(transport: transport, clock: clock)
        do { try await analyze(client); XCTFail("Quota ignored") } catch is AnalysisDeferred {}
        clock.date = Date(timeIntervalSince1970: 86_406)
        transport.quotaStatus = 503
        try await analyze(client)
        XCTAssertEqual(transport.postTimes.count, 1)
    }
    func testFreeQuotaDoesNotBlockAnExplicitSwitchToPaidModel() async throws {
        let clock = VirtualAnalysisClock()
        let transport = RateLimitTransport(clock: clock)
        transport.remaining = 0
        let client = OpenRouterClient(transport: transport, clock: clock)
        do { try await analyze(client); XCTFail("Quota ignored") } catch is AnalysisDeferred {}
        var settings = Settings(); settings.model = "openai/gpt-4.1-mini"
        _ = try await client.analyze(note: note, repository: "kroco-edu/app", labels: [], settings: settings, key: "test-key")
        XCTAssertEqual(transport.postTimes.count, 1)
    }
    func testPauseWhilePacingDoesNotSendAnotherRequest() async throws {
        let clock = VirtualAnalysisClock()
        let transport = RateLimitTransport(clock: clock)
        let client = OpenRouterClient(transport: transport, clock: clock)
        try await analyze(client)
        clock.cancelSleep = true
        do { try await analyze(client); XCTFail("Cancelled pacing sent a request") } catch is CancellationError {}
        XCTAssertEqual(transport.postTimes.count, 1)
    }
    func testRetryDeadlineTakesPrecedenceOverLongPollingInterval() {
        let now = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(AnalysisScheduling.nextScanDelay(interval: 86_400, retryAt: now.addingTimeInterval(300), now: now), 300)
        XCTAssertEqual(AnalysisScheduling.nextScanDelay(interval: 300, retryAt: nil, now: now), 300)
        XCTAssertEqual(AnalysisScheduling.nextScanDelay(interval: 300, retryAt: now.addingTimeInterval(-1), now: now), 0)
        XCTAssertEqual(AnalysisScheduling.nextScanDelay(interval: 300, retryAt: now.addingTimeInterval(-1), now: now, isBusy: true), 5)
    }
    func testSlowQuotaRefreshCannotReturnAnAlreadyExpiredRetry() async throws {
        let clock = VirtualAnalysisClock()
        let transport = RateLimitTransport(clock: clock)
        transport.quotaRefreshDelay = 90
        transport.responses = [(429, [:], "")]
        let client = OpenRouterClient(transport: transport, clock: clock)
        do { try await analyze(client); XCTFail("Rate limit ignored") }
        catch let deferred as AnalysisDeferred { XCTAssertGreaterThan(deferred.retryAt, clock.now()) }
    }
}
