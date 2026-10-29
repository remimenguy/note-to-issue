import XCTest
@testable import NoteToIssueCore

final class HTTPStub: HTTPTransport {
    var requests: [URLRequest] = []
    var status = 200
    var response: Data
    init(_ response: Data) { self.response = response }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if request.url?.path == "/api/v1/key" {
            return (Data(#"{"data":{"free_model_daily_requests":{"remaining":50}}}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        return (response, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

final class CommandStub: CommandRunning {
    var calls: [(String, [String], Data?)] = []
    var responses: [Data]
    init(_ values: [String]) { responses = values.map { Data($0.utf8) } }
    func run(executable: String, arguments: [String], input: Data?, timeout: Double) async throws -> Data {
        calls.append((executable, arguments, input))
        guard !responses.isEmpty else { throw AppError.message("Unexpected command") }
        return responses.removeFirst()
    }
}

final class ServiceTests: XCTestCase {
    let note = Note(id: "id", title: "Bug", text: "Le bouton de connexion plante", modifiedAt: 1)
    let draftJSON = #"{"isIssue":true,"confidence":0.98,"reason":"Bug précis","title":"Corriger la connexion","body":"Le bouton plante.","labels":["bug"]}"#
    func envelope(content: String, finish: String = "stop") throws -> Data {
        try JSONSerialization.data(withJSONObject: ["choices": [["finish_reason": finish, "message": ["content": content]]]])
    }

    func testOpenRouterUsesStrictSchemaAndValidatesResponse() async throws {
        let transport = HTTPStub(try envelope(content: draftJSON))
        let draft = try await OpenRouterClient(transport: transport).analyze(note: note, repository: "kroco-edu/app", labels: ["bug"], settings: Settings(), key: "test-key")
        XCTAssertEqual(draft.title, "Corriger la connexion")
        let request = try XCTUnwrap(transport.requests.first(where: { $0.httpMethod == "POST" }))
        XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        let format = try XCTUnwrap(body["response_format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        let schema = try XCTUnwrap(format["json_schema"] as? [String: Any])
        XCTAssertEqual(schema["strict"] as? Bool, true)
        XCTAssertEqual((body["provider"] as? [String: Any])?["require_parameters"] as? Bool, true)
    }

    func testOpenRouterRejectsHTTPErrorMalformedTruncatedAndInventedLabels() async throws {
        let cases: [(Data, Int)] = [
            (try envelope(content: draftJSON), 401),
            (Data("{}".utf8), 200),
            (try envelope(content: "not json"), 200),
            (try envelope(content: draftJSON, finish: "length"), 200),
            (try envelope(content: draftJSON.replacingOccurrences(of: "bug\"", with: "invented\"")), 200)
        ]
        for (data, status) in cases {
            let transport = HTTPStub(data); transport.status = status
            do {
                _ = try await OpenRouterClient(transport: transport).analyze(note: note, repository: "kroco-edu/app", labels: ["bug"], settings: Settings(), key: "test")
                XCTFail("Invalid response accepted")
            } catch {}
        }
    }

    func testGitHubPaginatesClosedIssuesAndChecksExactMarker() async throws {
        let first = (0..<100).map { ["body": "other", "html_url": "https://github.com/kroco-edu/app/issues/\($0+1)"] }
        let firstJSON = String(decoding: try JSONSerialization.data(withJSONObject: first), as: UTF8.self)
        let secondJSON = String(decoding: try JSONSerialization.data(withJSONObject: [["body": "Details\n\(note.marker)", "html_url": "https://github.com/kroco-edu/app/issues/101"]]), as: UTF8.self)
        let runner = CommandStub([firstJSON, secondJSON])
        let url = try await GitHubClient(runner: runner, executable: "/fake/gh").find(repository: "kroco-edu/app", marker: note.marker)
        XCTAssertEqual(url?.absoluteString, "https://github.com/kroco-edu/app/issues/101")
        XCTAssertEqual(runner.calls.count, 2)
        XCTAssertTrue(runner.calls[1].1.contains(where: { $0.contains("state=all") && $0.contains("page=2") }))
    }

    func testGitHubCreateUsesStdinAndMarker() async throws {
        let runner = CommandStub([#"{"html_url":"https://github.com/kroco-edu/app/issues/42"}"#])
        let draft = try JSONDecoder().decode(Draft.self, from: Data(draftJSON.utf8))
        let url = try await GitHubClient(runner: runner, executable: "/fake/gh").create(repository: "kroco-edu/app", draft: draft, marker: note.marker)
        XCTAssertEqual(url.absoluteString, "https://github.com/kroco-edu/app/issues/42")
        let call = try XCTUnwrap(runner.calls.first)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(call.2)) as? [String: Any])
        XCTAssertEqual(body["body"] as? String, draft.body + "\n\n" + note.marker)
        XCTAssertEqual(body["labels"] as? [String], ["bug"])
        XCTAssertFalse(call.1.joined().contains(draft.body))
    }

    func testNotesClientPassesCacheAndDecodesNotes() async throws {
        let runner = CommandStub([#"[{"id":"id","title":"Bug","text":"texte","modifiedAt":1,"folder":"Dev"}]"#])
        let notes = try await NotesClient(runner: runner).read(settings: Settings(), known: ["old": 5])
        XCTAssertEqual(notes.first?.folder, "Dev")
        let arguments = try XCTUnwrap(runner.calls.first?.1)
        let payload = try XCTUnwrap(arguments.last?.data(using: .utf8))
        let config = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        XCTAssertEqual(config["known"] as? [String: Double], ["old": 5])
        XCTAssertEqual(config["limit"] as? Int, 10)
    }

    func testProcessRunnerReadsOutputAndTimesOut() async throws {
        let runner = ProcessRunner()
        let data = try await runner.run(executable: "/usr/bin/printf", arguments: ["hello"], input: nil, timeout: 2)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "hello")
        do {
            _ = try await runner.run(executable: "/bin/sleep", arguments: ["3"], input: nil, timeout: 0.05)
            XCTFail("Timeout not enforced")
        } catch {}
    }

    func testManualReanalysisReadsOnlyTheRequestedFreshNote() async throws {
        let runner = CommandStub([#"[{"id":"id","title":"Bug","text":"updated text","modifiedAt":2,"folder":"Dev"}]"#])
        let fresh = try await NotesClient(runner: runner).readOne(id: "id", settings: Settings())
        XCTAssertEqual(fresh.text, "updated text")
        let config = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(runner.calls[0].1.last!.utf8)) as? [String: Any])
        XCTAssertEqual(config["onlyID"] as? String, "id")
    }
}
