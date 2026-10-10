import Foundation

/// Loader-owned envelope for trusted fixture pages. Security tests construct raw envelopes directly.
enum ProbeSourceFixture {
    static func metadata(url: String) -> [String: Any] {
        ["loader": 8, "origin": "https://claude.ai", "url": url, "processId": 1, "routingId": 1]
    }

    static func entry(_ raw: [String: Any]) -> [String: Any] {
        var result = raw
        if let url = raw["url"] as? String { result["source"] = metadata(url: url) }
        return result
    }
}
