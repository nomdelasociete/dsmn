import Foundation
import TOMLKit

/// Validates TOML semantics while preserving the user's original text.
/// The scanner only locates complete statements; TOMLKit owns syntax and identity.
enum CodexFeatureConfiguration {
    enum ConfigurationError: LocalizedError {
        case invalidTOML
        case unsupportedEdit
        case semanticMismatch

        var errorDescription: String? {
            switch self {
            case .invalidTOML:
                "invalid TOML; fix the configuration before installing Codex hooks"
            case .unsupportedEdit:
                "cannot safely edit this features.hooks representation; enable it manually or use a [features] table with a boolean hooks key"
            case .semanticMismatch:
                "could not verify that only features.hooks changed; configuration was not written"
            }
        }
    }

    static func hooksEnabled(in text: String) throws -> Bool {
        try parse(text)["features"]?.table?["hooks"]?.bool == true
    }

    static func enablingHooks(in original: String) throws -> String {
        let parsed = try parse(original)
        if parsed["features"]?.table?["hooks"]?.bool == true {
            return original
        }

        let bytes = Array(original.utf8)
        let statements = statements(in: bytes)
        let newline = original.contains("\r\n") ? "\r\n" : "\n"
        var header: Range<Int>?
        var flagRange: Range<Int>?

        for statement in statements {
            let text = String(decoding: bytes[statement], as: UTF8.self)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("[") {
                if header != nil { break }
                if let table = try? TOMLTable(string: text),
                   table.keys == ["features"], table["features"]?.table?.isEmpty == true {
                    header = statement
                }
            } else if header != nil,
                      let entry = try? TOMLTable(string: text),
                      entry.keys == ["hooks"], entry["hooks"]?.bool == false,
                      let equals = assignmentOffset(in: bytes, range: statement) {
                var start = equals + 1
                while start < statement.upperBound && (bytes[start] == 32 || bytes[start] == 9) { start += 1 }
                if start + 5 <= statement.upperBound, Array(bytes[start..<(start + 5)]) == Array("false".utf8) {
                    flagRange = start..<(start + 5)
                }
                break
            }
        }

        var edited = bytes
        if let flagRange {
            edited.replaceSubrange(flagRange, with: "true".utf8)
        } else if let header, parsed["features"]?.table?["hooks"] == nil {
            let separator = header.upperBound > 0 && bytes[header.upperBound - 1] == 10 ? "" : newline
            edited.insert(contentsOf: (separator + "hooks = true" + newline).utf8, at: header.upperBound)
        } else if parsed["features"] == nil {
            let separator = bytes.isEmpty || bytes.last == 10 ? "" : newline
            edited.append(contentsOf: (separator + "[features]" + newline + "hooks = true" + newline).utf8)
        } else {
            throw ConfigurationError.unsupportedEdit
        }

        let candidate = String(decoding: edited, as: UTF8.self)
        let validated: TOMLTable
        do { validated = try parse(candidate) } catch { throw ConfigurationError.unsupportedEdit }
        let features = parsed["features"]?.table ?? TOMLTable()
        features["hooks"] = true
        parsed["features"] = features
        guard validated == parsed else { throw ConfigurationError.semanticMismatch }
        return candidate
    }

    private static func parse(_ text: String) throws -> TOMLTable {
        // TOMLKit's C-string entry point would otherwise stop at an embedded NUL.
        guard !text.utf8.contains(0) else { throw ConfigurationError.invalidTOML }
        do {
            return try TOMLTable(string: text)
        } catch {
            // Parser diagnostics may include user values; never expose them.
            throw ConfigurationError.invalidTOML
        }
    }

    /// Newlines inside arrays, inline tables, or multiline strings are not statement boundaries.
    private static func statements(in bytes: [UInt8]) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var start = 0
        var index = 0
        var quote: UInt8?
        var multiline = false
        var depth = 0
        var comment = false
        while index < bytes.count {
            let byte = bytes[index]
            if comment {
                if byte == 10 { comment = false }
            } else if let delimiter = quote {
                if delimiter == 34 && byte == 92 {
                    index += 2
                    continue
                }
                if byte == delimiter {
                    if multiline {
                        var end = index
                        while end < bytes.count && bytes[end] == delimiter { end += 1 }
                        if end - index >= 3 {
                            quote = nil
                            multiline = false
                        }
                        index = end
                        continue
                    }
                    quote = nil
                }
            } else {
                switch byte {
                case 35: comment = true
                case 34, 39:
                    quote = byte
                    multiline = index + 2 < bytes.count && bytes[index + 1] == byte && bytes[index + 2] == byte
                    if multiline { index += 2 }
                case 91, 123: depth += 1
                case 93, 125: depth -= 1
                default: break
                }
            }
            if byte == 10 && quote == nil && depth == 0 {
                result.append(start..<(index + 1))
                start = index + 1
            }
            index += 1
        }
        if start < bytes.count { result.append(start..<bytes.count) }
        return result
    }

    /// Locate the assignment after a potentially quoted key, ignoring '=' in that key.
    private static func assignmentOffset(in bytes: [UInt8], range: Range<Int>) -> Int? {
        var quote: UInt8?
        var index = range.lowerBound
        while index < range.upperBound {
            let byte = bytes[index]
            if let delimiter = quote {
                if delimiter == 34 && byte == 92 { index += 2; continue }
                if byte == delimiter { quote = nil }
            } else if byte == 34 || byte == 39 {
                quote = byte
            } else if byte == 61 {
                return index
            }
            index += 1
        }
        return nil
    }
}
