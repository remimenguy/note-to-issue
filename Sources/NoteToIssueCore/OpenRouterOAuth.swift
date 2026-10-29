import Foundation
import CryptoKit
import Security

public struct PKCE: Sendable {
    public let verifier: String
    public let state: String
    public init() throws {
        verifier = try Self.random()
        state = try Self.random()
    }
    private static func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw AppError.message("Génération aléatoire impossible.")
        }
        return base64URL(Data(bytes))
    }
    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    public static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }
    public func authorizationURL(callback: URL) -> URL {
        var url = URLComponents(string: "https://openrouter.ai/auth")!
        url.queryItems = [
            URLQueryItem(name: "callback_url", value: callback.absoluteString),
            URLQueryItem(name: "code_challenge", value: Self.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "key_label", value: "Note to Issue")
        ]
        return url.url!
    }
    public static func code(from url: URL, callback: URL, state: String) throws -> String {
        guard url.scheme == callback.scheme, url.host == callback.host, url.port == callback.port,
              url.path == callback.path, url.user == nil, url.password == nil, url.fragment == nil,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              items.filter({ $0.name == "state" }).count == 1,
              items.first(where: { $0.name == "state" })?.value == state,
              items.filter({ $0.name == "code" }).count == 1,
              let code = items.first(where: { $0.name == "code" })?.value,
              !code.isEmpty, code.count <= 4096, !items.contains(where: { $0.name == "error" }) else {
            throw AppError.message("Retour OAuth invalide. Recommence la connexion.")
        }
        return code
    }
}

public struct OpenRouterOAuth {
    private let transport: HTTPTransport
    public init(transport: HTTPTransport = URLSessionTransport()) { self.transport = transport }
    public func exchange(code: String, verifier: String) async throws -> String {
        try Task.checkCancellation()
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/auth/keys")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["code": code, "code_verifier": verifier, "code_challenge_method": "S256"])
        let (data, response) = try await transport.send(request)
        try Task.checkCancellation()
        guard response.statusCode == 200, data.count <= 32_768 else {
            throw AppError.message("Connexion OpenRouter refusée (HTTP \(response.statusCode)). Recommence l'autorisation dans le navigateur.")
        }
        struct Result: Decodable { let key: String }
        guard let result = try? JSONDecoder().decode(Result.self, from: data), !result.key.isEmpty,
              result.key.count <= 4096, !result.key.contains("\n"), !result.key.contains("\r") else {
            throw AppError.message("Réponse OAuth OpenRouter invalide.")
        }
        return result.key
    }
}
