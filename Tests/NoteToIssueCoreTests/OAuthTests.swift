import XCTest
@testable import NoteToIssueCore

final class OAuthTests: XCTestCase {
    func testPKCEChallengeMatchesRFC7636Vector() throws {
        XCTAssertEqual(PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let pkce = try PKCE()
        XCTAssertTrue((43...128).contains(pkce.verifier.count))
        XCTAssertNotEqual(pkce.verifier, try PKCE().verifier)
        let callback = URL(string: "http://127.0.0.1:1234/callback")!
        let url = pkce.authorizationURL(callback: callback)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(query.first { $0.name == "callback_url" }?.value, callback.absoluteString)
        XCTAssertEqual(query.first { $0.name == "code_challenge_method" }?.value, "S256")
        XCTAssertEqual(query.first { $0.name == "state" }?.value, pkce.state)
        XCTAssertFalse(url.absoluteString.contains(pkce.verifier))
    }

    func testCallbackRequiresExactOriginPathStateAndOneCode() throws {
        let expected = URL(string: "http://127.0.0.1:1234/callback/random")!
        let good = URL(string: expected.absoluteString + "?state=expected&code=once")!
        XCTAssertEqual(try PKCE.code(from: good, callback: expected, state: "expected"), "once")
        for value in [
            "http://127.0.0.1:1234/callback/random?state=wrong&code=once",
            "http://127.0.0.1:1234/callback/random?code=once",
            "http://127.0.0.1:1234/callback/random?state=expected&code=one&code=two",
            "http://127.0.0.1:1234/other?state=expected&code=once",
            "http://evil.test:1234/callback/random?state=expected&code=once"
        ] {
            XCTAssertThrowsError(try PKCE.code(from: URL(string: value)!, callback: expected, state: "expected"))
        }
    }

    func testExchangeUsesVerifierWithoutClientSecret() async throws {
        let transport = HTTPStub(Data(#"{"key":"test-user-key","user_id":"one"}"#.utf8))
        let key = try await OpenRouterOAuth(transport: transport).exchange(code: "once", verifier: "verifier")
        XCTAssertEqual(key, "test-user-key")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/auth/keys")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let data = try XCTUnwrap(request.httpBody)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(payload, ["code": "once", "code_verifier": "verifier", "code_challenge_method": "S256"])
    }

    func testExchangeErrorsDoNotExposeServerBody() async throws {
        let transport = HTTPStub(Data("sensitive-response".utf8)); transport.status = 403
        do {
            _ = try await OpenRouterOAuth(transport: transport).exchange(code: "once", verifier: "verifier")
            XCTFail("Error response accepted")
        } catch { XCTAssertFalse(error.localizedDescription.contains("sensitive-response")) }
    }

    func testLoopbackReceivesCallbackAndStops() async throws {
        let server = try OAuthCallbackServer(state: "expected", timeout: 5)
        let callback = try await server.start()
        XCTAssertEqual(callback.host, "127.0.0.1")
        let requestURL = URL(string: callback.absoluteString + "?state=expected&code=once")!
        async let waiting = server.waitForCode()
        let (data, response) = try await URLSession.shared.data(from: requestURL)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("once"))
        let code = try await waiting
        XCTAssertEqual(code, "once")
        server.cancel()
    }

    func testCancelledExchangeNeverReturnsCredential() async throws {
        let transport = DelayedOAuthTransport()
        let task = Task { try await OpenRouterOAuth(transport: transport).exchange(code: "once", verifier: "verifier") }
        try await Task.sleep(for: .milliseconds(10))
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled exchange returned a credential") }
        catch is CancellationError {}
    }
}

private struct DelayedOAuthTransport: HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        // Simulate a dependency that completes even after the caller is cancelled.
        await withCheckedContinuation { continuation in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { continuation.resume() }
        }
        return (Data(#"{"key":"test-key"}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
