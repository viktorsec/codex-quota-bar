import Foundation

struct ResetCredits: Codable {
    struct Credit: Identifiable, Codable {
        let id: String
        let expiresAt: Date?
    }

    // The service can cap the detail rows, so their count is not authoritative.
    let availableCount: Int
    let credits: [Credit]

    func nextExpiration(after now: Date) -> Date? {
        guard availableCount > 0 else { return nil }
        return credits.compactMap(\.expiresAt).filter { $0 > now }.min()
    }

    static func parse(_ response: [String: Any]) -> ResetCredits? {
        guard let summary = response["rateLimitResetCredits"] as? [String: Any],
              let count = summary["availableCount"] as? Int, count >= 0 else { return nil }
        let rows = summary["credits"] as? [[String: Any]] ?? []
        let credits = rows.compactMap { row -> Credit? in
            guard row["status"] as? String == "available",
                  let id = row["id"] as? String else { return nil }
            let expiration = (row["expiresAt"] as? Double)
                .flatMap { $0.isFinite ? Date(timeIntervalSince1970: $0) : nil }
            return Credit(id: id, expiresAt: expiration)
        }.sorted {
            let lhs = $0.expiresAt ?? .distantFuture
            let rhs = $1.expiresAt ?? .distantFuture
            return lhs == rhs ? $0.id < $1.id : lhs < rhs
        }
        return ResetCredits(availableCount: count, credits: credits)
    }
}
