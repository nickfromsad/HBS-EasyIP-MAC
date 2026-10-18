import Foundation

/// Looks up the latest GitHub release, so the header can point out a newer version.
enum UpdateCheck {
    struct Release: Equatable {
        let version: String
        let url: URL
    }

    private static let latestRelease = URL(string: "https://api.github.com/repos/nickfromsad/HBS-EasyIP-MAC/releases/latest")!

    /// The latest release if it is newer than `current`, nil otherwise (also when offline).
    static func newerRelease(than current: String) async -> Release? {
        guard isVersion(current) else { return nil }   // "dev" builds don't nag
        var request = URLRequest(url: latestRelease, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else { return nil }
        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return isNewer(latest, than: current) ? Release(version: latest, url: page) : nil
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let lhs = numbers(a), rhs = numbers(b)
        for i in 0..<max(lhs.count, rhs.count) {
            let x = i < lhs.count ? lhs[i] : 0, y = i < rhs.count ? rhs[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func isVersion(_ string: String) -> Bool { !numbers(string).isEmpty }

    private static func numbers(_ version: String) -> [Int] {
        version.split(separator: "-").first.map { $0.split(separator: ".").compactMap { Int($0) } } ?? []
    }
}
