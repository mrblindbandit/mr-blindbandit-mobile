import Foundation

/// Public photo and video addresses. Relative paths belong on the website, not the API host.
enum PublicMediaURL {
    static func httpsString(_ raw: String?) -> String? {
        normalize(raw)?.absoluteString
    }

    static func normalize(_ raw: String?) -> URL? {
        let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !s.isEmpty else { return nil }
        let lower = s.lowercased()
        if lower.hasPrefix("javascript:") || lower.hasPrefix("data:") || lower.hasPrefix("file:") || lower.hasPrefix("blob:") {
            return nil
        }
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            guard var components = URLComponents(string: s), let host = components.host?.lowercased() else { return nil }
            if components.scheme?.lowercased() == "http",
               host == "mrblindbandit.net" || host.hasSuffix(".mrblindbandit.net") {
                components.scheme = "https"
            }
            guard components.scheme?.lowercased() == "https" else { return nil }
            return components.url
        }
        if s.hasPrefix("//") { return normalize("https:" + s) }
        let path = s.hasPrefix("/") ? s : "/" + s
        if path.hasPrefix("/v1/") || path.hasPrefix("/api/") {
            return URL(string: path, relativeTo: AppConfig.apiBaseURL)?.absoluteURL
        }
        return URL(string: "https://mrblindbandit.net" + path)
    }

    /// First usable https address in an upload response, including a nested `data` object.
    static func firstHTTPS(in object: [String: Any]) -> String? {
        let keys = ["avatar_url", "url", "public_url", "content_url"]
        for key in keys {
            if let value = object[key] as? String, let https = httpsString(value) { return https }
        }
        if let data = object["data"] as? [String: Any], let nested = firstHTTPS(in: data) { return nested }
        return nil
    }
}
