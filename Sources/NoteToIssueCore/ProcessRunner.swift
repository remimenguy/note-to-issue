import Foundation
import Darwin

public protocol CommandRunning {
    func run(executable: String, arguments: [String], input: Data?, timeout: Double) async throws -> Data
}

public struct ProcessRunner: CommandRunning {
    public init() {}
    public func run(executable: String, arguments: [String], input: Data? = nil, timeout: Double = 60) async throws -> Data {
        try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            var environment = ProcessInfo.processInfo.environment
            environment["GH_PROMPT_DISABLED"] = "1"
            environment["GH_HOST"] = "github.com"
            process.environment = environment
            let output = Pipe(), stdin = Pipe()
            process.standardOutput = output
            process.standardError = output
            process.standardInput = stdin
            try process.run()
            let watchdog = DispatchWorkItem {
                if process.isRunning {
                    process.terminate()
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
                        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                    }
                }
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: watchdog)
            defer { watchdog.cancel() }
            // Input stays in a pipe, never in a shell expression or a temporary file.
            if let input { try stdin.fileHandleForWriting.write(contentsOf: input) }
            try stdin.fileHandleForWriting.close()
            var data = Data()
            while let chunk = try output.fileHandleForReading.read(upToCount: 65_536), !chunk.isEmpty {
                guard data.count + chunk.count <= 8_000_000 else {
                    process.terminate()
                    throw AppError.message("Réponse externe trop volumineuse.")
                }
                data.append(chunk)
            }
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let name = URL(fileURLWithPath: executable).lastPathComponent
                if name == "osascript" {
                    if String(decoding: data, as: UTF8.self).contains("Notes account not found") {
                        throw AppError.message("Compte Notes introuvable. Dans les réglages, utilise le nom exact du compte affiché dans Apple Notes.")
                    }
                    if String(decoding: data, as: UTF8.self).contains("Notes folder not found") {
                        throw AppError.message("Dossier Notes introuvable ou ambigu. Vérifie son nom exact, ou laisse le filtre vide.")
                    }
                    throw AppError.message("Accès Notes impossible. Vérifie le compte, les dossiers et Réglages Système → Confidentialité et sécurité → Automatisation → Note to Issue → Notes.")
                }
                throw AppError.message("\(name) a échoué ou dépassé le délai. Vérifie la connexion et les droits GitHub avec gh auth status.")
            }
            return data
        }.value
    }
}
