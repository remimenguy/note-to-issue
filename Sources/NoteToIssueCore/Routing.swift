import Foundation

public enum Routing {
    public static func validate(_ value: String) throws -> String {
        let repo = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})/[A-Za-z0-9_.-]{1,100}$"#
        guard repo.range(of: pattern, options: .regularExpression) != nil,
              ![".", ".."].contains(String(repo.split(separator: "/").last ?? "")) else {
            throw AppError.message("Dépôt invalide. Utilise owner/name, par exemple kroco-edu/app.")
        }
        return repo.lowercased()
    }

    public static func repository(for text: String, defaultRepository: String) throws -> String {
        let fallback = try validate(defaultRepository)
        let patterns = [
            #"(?im)^\s*(?:repo|repository|dépôt|depot)\s*:\s*([^\r\n]*)"#,
            #"(?i)(?:dans\s+le\s+(?:repo|dépôt|depot)|(?:create|créer|crée)\s+(?:l['’])?(?:issue|ticket)\s+(?:in|dans)(?:\s+(?:le\s+)?(?:repo|repository|dépôt|depot))?)\s+([^\s,;!?]+)"#
        ]
        var destinations = Set<String>()
        for pattern in patterns {
            let regex = try NSRegularExpression(pattern: pattern)
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range(at: 1), in: text) else { continue }
                var value = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if value.hasPrefix("https://github.com/") { value.removeFirst("https://github.com/".count) }
                destinations.insert(try validate(value))
            }
        }
        guard destinations.count <= 1 else { throw AppError.message("Plusieurs destinations dans cette note. Garde une seule directive repo: owner/name.") }
        return destinations.first ?? fallback
    }
}
