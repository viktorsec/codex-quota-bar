import Foundation

struct QuotaWindow: Identifiable {
    let id: String
    let title: String
    let usedPercent: Double
    let resetsAt: Date?
    let windowDurationMins: Int?

    var remainingPercent: Int { Int((100 - usedPercent).rounded(.down)) }

    static func parse(_ response: [String: Any]) -> [QuotaWindow] {
        // Newer servers may return multiple metered buckets. Avoid duplicating
        // the backward-compatible single bucket when both views are present.
        let buckets: [(String, [String: Any])]
        if let multiple = response["rateLimitsByLimitId"] as? [String: [String: Any]], !multiple.isEmpty {
            buckets = multiple.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        } else if let single = response["rateLimits"] as? [String: Any] {
            buckets = [(single["limitId"] as? String ?? "codex", single)]
        } else {
            return []
        }
        return buckets.flatMap { bucketID, bucket in
            ["primary", "secondary"].compactMap { key in
                guard let window = bucket[key] as? [String: Any],
                      let used = window["usedPercent"] as? Double,
                      used.isFinite, (0...100).contains(used) else { return nil }
                let minutes = window["windowDurationMins"] as? Int
                let duration: String
                switch minutes {
                case 10_080: duration = "Weekly"
                case let value? where value > 0 && value % 60 == 0: duration = "\(value / 60)-hour"
                case let value? where value > 0: duration = "\(value)-minute"
                default: duration = key == "primary" ? "Primary" : "Secondary"
                }
                let prefix = buckets.count > 1 ? "\(bucket["limitName"] as? String ?? bucketID) · " : ""
                let reset = (window["resetsAt"] as? Double).map(Date.init(timeIntervalSince1970:))
                return QuotaWindow(
                    id: "\(bucketID).\(key)", title: prefix + duration,
                    usedPercent: used, resetsAt: reset, windowDurationMins: minutes
                )
            }
        }
    }
}

