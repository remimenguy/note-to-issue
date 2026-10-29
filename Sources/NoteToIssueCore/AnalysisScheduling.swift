import Foundation

public protocol AnalysisClock {
    func now() -> Date
    func sleep(seconds: Double) async throws
}

public struct SystemAnalysisClock: AnalysisClock {
    public init() {}
    public func now() -> Date { Date() }
    public func sleep(seconds: Double) async throws { try await Task.sleep(for: .seconds(seconds)) }
}

public struct AnalysisDeferred: LocalizedError, Sendable {
    public let retryAt: Date
    public let message: String
    public init(retryAt: Date, message: String) { self.retryAt = retryAt; self.message = message }
    public var errorDescription: String? { message }
}

public enum AnalysisScheduling {
    public static func nextScanDelay(interval: Double, retryAt: Date?, now: Date, isBusy: Bool = false) -> Double {
        if isBusy { return 5 }
        if let retryAt { return max(0, retryAt.timeIntervalSince(now)) }
        return interval
    }

    static func nextUTCDay(after date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.startOfDay(for: date).addingTimeInterval(86_405)
    }

    static func serverRetryDate(response: HTTPURLResponse, now: Date) -> Date? {
        var candidates: [Date] = []
        if let value = response.value(forHTTPHeaderField: "Retry-After") {
            if let seconds = Double(value), seconds.isFinite, (0...2_678_400).contains(seconds) {
                candidates.append(now.addingTimeInterval(seconds))
            } else {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
                if let date = formatter.date(from: value) { candidates.append(date) }
            }
        }
        if let raw = response.value(forHTTPHeaderField: "X-RateLimit-Reset"), let number = Double(raw), number.isFinite {
            candidates.append(Date(timeIntervalSince1970: number > 1_000_000_000_000 ? number / 1000 : number))
        }
        return candidates.filter { $0 > now && $0.timeIntervalSince(now) <= 2_678_400 }.max()
    }
}
