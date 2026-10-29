import Foundation
import Network

/// A loopback-only receiver, alive for at most one interactive login.
public final class OAuthCallbackServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "NoteToIssue.OAuth", qos: .utility)
    private let listener: NWListener
    private let state: String
    private let timeout: Double
    private var callback: URL?
    private var startContinuation: CheckedContinuation<URL, Error>?
    private var codeContinuation: CheckedContinuation<String, Error>?
    private var result: Result<String, Error>?
    private var connections: [UUID: NWConnection] = [:]
    private var timeoutWork: DispatchWorkItem?

    public init(state: String, timeout: Double = 180) throws {
        self.state = state; self.timeout = timeout
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    public func start() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.startContinuation = continuation
                self.listener.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        guard let port = self.listener.port else { self.finish(.failure(AppError.message("Port OAuth indisponible."))); return }
                        self.callback = URL(string: "http://127.0.0.1:\(port.rawValue)/oauth/\(UUID().uuidString)")!
                        self.startContinuation?.resume(returning: self.callback!)
                        self.startContinuation = nil
                    case .failed:
                        self.finish(.failure(AppError.message("Impossible d'ouvrir le retour OAuth local.")))
                    default: break
                    }
                }
                self.listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
                let watchdog = DispatchWorkItem { [weak self] in self?.finish(.failure(AppError.message("Connexion expirée. Recommence et autorise OpenRouter dans les 3 minutes."))) }
                self.timeoutWork = watchdog
                self.queue.asyncAfter(deadline: .now() + self.timeout, execute: watchdog)
                self.listener.start(queue: self.queue)
            }
        }
    }

    public func waitForCode() async throws -> String {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    if let result = self.result { continuation.resume(with: result) }
                    else { self.codeContinuation = continuation }
                }
            }
        } onCancel: { self.cancel() }
    }
    public func cancel() {
        queue.async { self.finish(.failure(CancellationError())) }
    }
    private func finish(_ result: Result<String, Error>) {
        guard self.result == nil else { return }
        self.result = result
        timeoutWork?.cancel(); timeoutWork = nil
        listener.cancel()
        startContinuation?.resume(throwing: AppError.message("Connexion OAuth interrompue.")); startContinuation = nil
        codeContinuation?.resume(with: result); codeContinuation = nil
        for connection in connections.values { connection.cancel() }
        connections.removeAll()
    }
    private func accept(_ connection: NWConnection) {
        guard connections.count < 8, result == nil else { connection.cancel(); return }
        let id = UUID()
        connections[id] = connection
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 5) { [weak self, weak connection] in
            connection?.cancel(); self?.connections[id] = nil
        }
        receive(connection, id: id, buffer: Data())
    }
    private func receive(_ connection: NWConnection, id: UUID, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, complete, error in
            guard let self else { connection.cancel(); return }
            var buffer = buffer
            if let data { buffer.append(data) }
            guard buffer.count <= 8192, error == nil else { connection.cancel(); self.connections[id] = nil; return }
            guard let request = String(data: buffer, encoding: .utf8), request.contains("\r\n\r\n") else {
                if complete { connection.cancel(); self.connections[id] = nil }
                else { self.receive(connection, id: id, buffer: buffer) }
                return
            }
            let parts = request.components(separatedBy: "\r\n")[0].split(separator: " ")
            var code: String?
            if parts.count == 3, parts[0] == "GET", parts[1].hasPrefix("/"),
               let callback = self.callback,
               let url = URL(string: "http://127.0.0.1:\(callback.port!)" + parts[1]) {
                code = try? PKCE.code(from: url, callback: callback, state: self.state)
            }
            let text = code == nil ? "Retour non valide. Reviens dans l'application." : "OpenRouter est connecte. Tu peux revenir dans Note to Issue."
            let status = code == nil ? "400 Bad Request" : "200 OK"
            let response = "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(text.utf8.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n\(text)"
            connection.send(content: Data(response.utf8), completion: .contentProcessed { [weak self] _ in
                connection.cancel(); self?.connections[id] = nil
                if let code { self?.finish(.success(code)) }
            })
        }
    }
}
