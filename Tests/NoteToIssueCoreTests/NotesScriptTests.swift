import XCTest
@testable import NoteToIssueCore

final class NotesScriptTests: XCTestCase {
    func script() async throws -> String {
        let stub = CommandStub(["[]"])
        _ = try await NotesClient(runner: stub).read(settings: Settings(), known: [:])
        let path = try XCTUnwrap(stub.calls.first?.1.dropLast().last)
        return try String(contentsOfFile: path, encoding: .utf8)
    }
    func runScript(accounts: [String]) async throws {
        let accountJSON = String(decoding: try JSONEncoder().encode(accounts), as: UTF8.self)
        let fixture = """
        var names = \(accountJSON);
        var objects = names.map(function(name) {
            var notes = {id:function(){return [];}, modificationDate:function(){return [];} };
            return {name:function(){return name;}, notes:notes};
        });
        function listAccounts(){return objects;}
        listAccounts.whose = function(q){return function(){return objects.filter(function(a){return a.name() === q.name;});};};
        function Application(){return {accounts:listAccounts};}
        """
        _ = try await evaluate(fixture: fixture, config: #"{"account":"iCloud","folder":"","known":{},"limit":0}"#)
    }
    func evaluate(fixture: String, config: String) async throws -> Data {
        let argument = String(decoding: try JSONEncoder().encode(config), as: UTF8.self)
        // Application is a protected global in JXA; shadow it inside a local function scope.
        let program = "(function(){\n" + fixture + "\n" + (try await script()) + "\nreturn run([" + argument + "]);\n})()"
        return try await ProcessRunner().run(executable: "/usr/bin/osascript", arguments: ["-l", "JavaScript", "-e", program], input: nil, timeout: 5)
    }
    func testRenamedICloudAccountIsDetected() async throws {
        try await runScript(accounts: ["iCloud & Example", "Work"])
    }
    func testAmbiguousICloudAccountsAreRejected() async throws {
        do { try await runScript(accounts: ["iCloud A", "iCloud B"]); XCTFail("Ambiguous account accepted") }
        catch {}
    }
    func testDeletedNoteIsExcludedBeforeReadingItsText() async throws {
        let fixture = """
        var notes = {
            id:function(){return ["deleted", "active"];},
            modificationDate:function(){return [new Date(1000), new Date(1000)];},
            byId:function(id){return {
                passwordProtected:function(){return false;},
                container:function(){return {name:function(){return id === "deleted" ? "Recently Deleted" : "Notes";}};},
                plaintext:function(){if(id === "deleted")throw Error("Deleted text must not be read");return "text";},
                modificationDate:function(){return new Date(1000);},name:function(){return "Title";}
            };}
        };
        var account = {name:function(){return "iCloud";},notes:notes};
        function Application(){return {accounts:{whose:function(){return function(){return [account];};}}};}
        """
        let data = try await evaluate(fixture: fixture, config: #"{"account":"iCloud","folder":"","known":{},"limit":10}"#)
        let notes = try JSONDecoder().decode([Note].self, from: data)
        XCTAssertEqual(notes.map(\.id), ["active"])
    }
}
