import Foundation

public protocol GitHubServing {
    func labels(repository: String) async throws -> [String]
    func find(repository: String, marker: String) async throws -> URL?
    func create(repository: String, draft: Draft, marker: String) async throws -> URL
}

public actor GitHubClient: GitHubServing {
    private let runner: CommandRunning
    private let executable: String?
    private var labelCache: [String: (Date, [String])] = [:]
    private var issueCache: [String: (Date, [RemoteIssue])] = [:]
    private struct Label: Decodable { let name: String }
    private struct RemoteIssue: Decodable { let body: String?; let html_url: String }

    public init(runner: CommandRunning = ProcessRunner(), executable: String? = nil) {
        self.runner = runner; self.executable = executable
    }
    public static func installedExecutable() throws -> String {
        for path in ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"] where FileManager.default.isExecutableFile(atPath: path) { return path }
        throw AppError.message("GitHub CLI manque. Installe-le avec brew install gh, puis gh auth login.")
    }
    private func api(_ endpoint: String, method: String = "GET", input: Data? = nil) async throws -> Data {
        var arguments = ["api", "--hostname", "github.com", "--method", method, endpoint]
        if input != nil { arguments += ["--input", "-"] }
        return try await runner.run(executable: executable ?? Self.installedExecutable(), arguments: arguments, input: input, timeout: 60)
    }
    public func labels(repository: String) async throws -> [String] {
        let repository = try Routing.validate(repository)
        if let cached = labelCache[repository], Date().timeIntervalSince(cached.0) < 300 { return cached.1 }
        var names: [String] = [], page = 1
        while true {
            let data = try await api("repos/\(repository)/labels?per_page=100&page=\(page)")
            let labels = try JSONDecoder().decode([Label].self, from: data)
            names += labels.map(\.name)
            if labels.count < 100 { break }
            page += 1
        }
        labelCache[repository] = (Date(), names)
        return names
    }
    public func find(repository: String, marker: String) async throws -> URL? {
        let repository = try Routing.validate(repository)
        var issues: [RemoteIssue]
        if let cached = issueCache[repository], Date().timeIntervalSince(cached.0) < 60 {
            issues = cached.1
        } else {
            issues = []; var page = 1
            while true {
                let data = try await api("repos/\(repository)/issues?state=all&per_page=100&page=\(page)")
                let batch = try JSONDecoder().decode([RemoteIssue].self, from: data)
                issues += batch
                if batch.count < 100 { break }
                page += 1
            }
            issueCache[repository] = (Date(), issues)
        }
        guard let match = issues.first(where: { $0.body?.contains(marker) == true }) else { return nil }
        return try Self.validIssueURL(match.html_url, repository: repository)
    }
    public func create(repository: String, draft: Draft, marker: String) async throws -> URL {
        let repository = try Routing.validate(repository)
        let input = try JSONSerialization.data(withJSONObject: ["title": draft.title, "body": draft.body + "\n\n" + marker, "labels": draft.labels])
        // Never retry this POST: a lost response may still mean GitHub created the issue.
        let data = try await api("repos/\(repository)/issues", method: "POST", input: input)
        let issue = try JSONDecoder().decode(RemoteIssue.self, from: data)
        let url = try Self.validIssueURL(issue.html_url, repository: repository)
        if let cached = issueCache[repository] {
            issueCache[repository] = (cached.0, cached.1 + [RemoteIssue(body: draft.body + "\n\n" + marker, html_url: issue.html_url)])
        }
        return url
    }
    static func validIssueURL(_ value: String, repository: String) throws -> URL {
        guard let url = URL(string: value), url.scheme == "https", url.host == "github.com",
              url.path.lowercased().hasPrefix("/\(repository.lowercased())/issues/"),
              Int(url.lastPathComponent) != nil else { throw AppError.message("URL d'issue GitHub invalide.") }
        return url
    }
}
