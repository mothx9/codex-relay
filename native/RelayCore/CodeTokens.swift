import Foundation

public struct CodeToken: Equatable, Sendable {
    public enum Kind: Sendable { case plain, keyword, string, number, comment, directive, command, flag, shellOperator, variable }
    public let text: String
    public let kind: Kind
}
/// A bounded lexical highlighter, not a language parser. Strings, comments,
/// numbers and a small language keyword vocabulary are recognized offline.
/// Unsupported syntax remains plain text and is always copied unchanged.
public enum CodeTokens {
    private static let common = Set("if else for while return break continue switch case default true false null nil import from as in try catch throw class struct enum public private static const let var void int float double char bool unsigned signed long short auto sizeof typedef template typename namespace using fn mut pub impl trait match use mod crate self Self async await func package defer go chan range map select interface type def with lambda pass None True False yield except finally elif and or not extends export function new typeof instanceof this super do then fi done echo set unset local source include define pragma __global__ __device__ __shared__ __host__".split(separator: " ").map(String.init))
    public static func tokenize(_ source: String, language: String?) -> [CodeToken] {
        // Unknown languages still get safe lexical coloring; source is intact.
        let hashComments = ["python", "py", "shell", "sh", "bash", "zsh", "yaml", "yml", "ruby", "rb"].contains(language?.lowercased() ?? "")
        let chars = Array(source)
        var result: [CodeToken] = []; var index = 0
        var runStart = 0; var runEnd = 0; var runKind: CodeToken.Kind?
        func emit(_ start: Int, _ end: Int, _ kind: CodeToken.Kind) {
            if runKind == kind && runEnd == start { runEnd = end; return }
            if let runKind { result.append(CodeToken(text: String(chars[runStart..<runEnd]), kind: runKind)) }
            runStart = start; runEnd = end; runKind = kind
        }
        while index < chars.count {
            let start = index; let c = chars[index]
            let next: Character? = index + 1 < chars.count ? chars[index + 1] : nil
            var kind: CodeToken.Kind = .plain
            if (c == "/" && next == "/") || (c == "#" && hashComments) {
                kind = .comment
                while index < chars.count && chars[index] != "\n" { index += 1 }
            } else if c == "/" && next == "*" {
                kind = .comment; index += 2
                while index < chars.count {
                    if chars[index] == "*" && index + 1 < chars.count && chars[index + 1] == "/" { index += 2; break }
                    index += 1
                }
            } else if c == "\"" || c == "'" || c == "`" {
                kind = .string; index += 1
                while index < chars.count {
                    if chars[index] == "\\" { index = min(index + 2, chars.count); continue }
                    let end = chars[index] == c; index += 1; if end { break }
                }
            } else if c.isNumber {
                kind = .number; index += 1
                while index < chars.count && (chars[index].isNumber || ".xabcdefABCDEF_".contains(chars[index])) { index += 1 }
            } else if c.isLetter || c == "_" || c == "#" {
                index += 1
                while index < chars.count && (chars[index].isLetter || chars[index].isNumber || chars[index] == "_") { index += 1 }
                let word = String(chars[start..<index])
                if c == "#" { kind = .directive } else if common.contains(word) { kind = .keyword }
            } else { index += 1 }
            emit(start, index, kind)
        }
        if let runKind { result.append(CodeToken(text: String(chars[runStart..<runEnd]), kind: runKind)) }
        return result
    }
}

/// Compact shell command coloring. This lexer preserves every byte and does not
/// execute, expand, or infer the result of a command.
public enum ShellTokens {
    public static func tokenize(_ source: String) -> [CodeToken] {
        let tokens = lex(source)
        let significant = tokens.indices.filter { !tokens[$0].text.allSatisfy(\.isWhitespace) }
        // Codex commonly reports a shell wrapper. Color the script inside its
        // final quoted argument without executing/unescaping or changing source.
        guard significant.count == 3, let first = significant.first, let last = significant.last,
              ["sh", "bash", "zsh"].contains(URL(fileURLWithPath: tokens[first].text).lastPathComponent),
              ["-c", "-lc", "-ic"].contains(tokens[significant[1]].text),
              tokens[last].kind == .string, tokens[last].text.count >= 2,
              let quote = tokens[last].text.first, tokens[last].text.last == quote else { return tokens }
        let script = String(tokens[last].text.dropFirst().dropLast())
        return Array(tokens[..<last]) + [CodeToken(text: String(quote), kind: .plain)]
            + lex(script) + [CodeToken(text: String(quote), kind: .plain)] + Array(tokens[(last + 1)...])
    }
    private static func lex(_ source: String) -> [CodeToken] {
        let chars = Array(source)
        var result: [CodeToken] = []
        var index = 0, commandExpected = true
        while index < chars.count {
            let start = index, character = chars[index]
            var kind: CodeToken.Kind = .plain
            if character.isWhitespace {
                while index < chars.count && chars[index].isWhitespace {
                    if chars[index] == "\n" { commandExpected = true }
                    index += 1
                }
            } else if character == "#" {
                kind = .comment
                while index < chars.count && chars[index] != "\n" { index += 1 }
            } else if character == "'" || character == "\"" {
                kind = .string; index += 1
                while index < chars.count {
                    if chars[index] == "\\" && character == "\"" { index = min(index + 2, chars.count); continue }
                    let end = chars[index] == character; index += 1
                    if end { break }
                }
                commandExpected = false
            } else if "|;&()<>".contains(character) {
                kind = .shellOperator; index += 1
                if "|;&(".contains(character) { commandExpected = true }
            } else {
                index += 1
                while index < chars.count && !chars[index].isWhitespace && !"|;&()<>'\"".contains(chars[index]) {
                    if chars[index] == "\\" { index = min(index + 2, chars.count) } else { index += 1 }
                }
                let word = String(chars[start..<index])
                if word.hasPrefix("$") { kind = .variable }
                else if commandExpected && !word.contains("=") { kind = .command; commandExpected = false }
                else if word.hasPrefix("-") { kind = .flag }
                else if Double(word) != nil { kind = .number }
            }
            result.append(CodeToken(text: String(chars[start..<index]), kind: kind))
        }
        return result
    }
}
