import Foundation

/// Minimal TOML subset parser used to load AirTerm's config file. Supports
/// - `# comments`
/// - `[section]` and `[section.sub]` dotted headers
/// - `key = value` entries where value is a quoted string, integer, double,
///   or `true`/`false`
///
/// This is intentionally not spec-complete. It covers our config shape.
enum TOML {
    enum ParseError: Error {
        case malformed(line: Int, reason: String)
    }

    static func parse(_ text: String) throws -> [String: Any] {
        var root: [String: Any] = [:]
        var path: [String] = []

        for (index, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = stripComment(rawLine.trimmingCharacters(in: .whitespaces))
            if line.isEmpty { continue }

            if line.hasPrefix("[") {
                guard line.hasSuffix("]") else {
                    throw ParseError.malformed(line: index + 1, reason: "section header missing ]")
                }
                let inside = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                path = inside.split(separator: ".").map { $0.trimmingCharacters(in: .whitespaces) }
                continue
            }

            guard let eqIdx = line.firstIndex(of: "=") else {
                throw ParseError.malformed(line: index + 1, reason: "expected '='")
            }
            let key = line[..<eqIdx].trimmingCharacters(in: .whitespaces)
            let rawValue = line[line.index(after: eqIdx)...].trimmingCharacters(in: .whitespaces)
            let value = parseValue(rawValue)
            insert(value, into: &root, path: path + [key])
        }
        return root
    }

    // MARK: - Value parsing

    private static func parseValue(_ s: String) -> Any {
        if s.hasPrefix("\""), s.hasSuffix("\""), s.count >= 2 {
            return unescape(String(s.dropFirst().dropLast()))
        }
        if s.hasPrefix("'"), s.hasSuffix("'"), s.count >= 2 {
            return String(s.dropFirst().dropLast())
        }
        if s == "true" { return true }
        if s == "false" { return false }
        if let i = Int(s) { return i }
        if let d = Double(s) { return d }
        return s  // raw fallback
    }

    private static func unescape(_ s: String) -> String {
        var out = ""
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c == "\\" {
                let next = s.index(after: i)
                guard next < s.endIndex else { break }
                switch s[next] {
                case "n": out.append("\n")
                case "t": out.append("\t")
                case "r": out.append("\r")
                case "\"": out.append("\"")
                case "\\": out.append("\\")
                default: out.append(s[next])
                }
                i = s.index(after: next)
            } else {
                out.append(c)
                i = s.index(after: i)
            }
        }
        return out
    }

    private static func stripComment(_ s: String) -> String {
        var inQuotes = false
        for (offset, ch) in s.enumerated() {
            if ch == "\"" { inQuotes.toggle() }
            if ch == "#" && !inQuotes {
                let idx = s.index(s.startIndex, offsetBy: offset)
                return String(s[..<idx]).trimmingCharacters(in: .whitespaces)
            }
        }
        return s
    }

    // MARK: - Dictionary path insertion

    private static func insert(_ value: Any, into dict: inout [String: Any], path: [String]) {
        guard !path.isEmpty else { return }
        if path.count == 1 {
            dict[path[0]] = value
            return
        }
        let head = path[0]
        var sub = dict[head] as? [String: Any] ?? [:]
        insert(value, into: &sub, path: Array(path.dropFirst()))
        dict[head] = sub
    }
}
