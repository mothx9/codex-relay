import Foundation

public struct PatchLine: Identifiable, Sendable, Equatable {
    public enum Kind: Sendable { case context, addition, deletion, hunk, metadata }
    public let id: Int
    public let text: String
    public let kind: Kind
    public let old: Int?
    public let new: Int?
}
public struct PatchFile: Identifiable, Sendable, Equatable {
    public let id: Int
    public var path: String
    public var lines: [PatchLine]
    public var additions: Int { lines.filter { $0.kind == .addition }.count }
    public var deletions: Int { lines.filter { $0.kind == .deletion }.count }
}
public enum PatchDocument {
    public static func parse(_ source: String, path: String = "Patch") -> [PatchFile] {
        var files: [PatchFile] = []
        var file = PatchFile(id: 0, path: path, lines: [])
        var old: Int?, new: Int?
        for (index, substring) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = String(substring)
            if line.hasPrefix("diff --git ") {
                if !file.lines.isEmpty { files.append(file) }
                file = PatchFile(id: index, path: path, lines: [])
                old = nil; new = nil
            }
            var kind: PatchLine.Kind = .metadata
            var oldLine: Int?, newLine: Int?
            if line.hasPrefix("+++ ") {
                let value = String(line.dropFirst(4)).components(separatedBy: "\t")[0]
                if value != "/dev/null" { file.path = value.hasPrefix("b/") ? String(value.dropFirst(2)) : value }
            } else if line.hasPrefix("--- ") {
                let value = String(line.dropFirst(4)).components(separatedBy: "\t")[0]
                if value != "/dev/null" { file.path = value.hasPrefix("a/") ? String(value.dropFirst(2)) : value }
            } else if line.hasPrefix("@@ ") {
                kind = .hunk
                let fields = line.split(separator: " ")
                old = fields.count > 2 ? location(fields[1], prefix: "-") : nil
                new = fields.count > 2 ? location(fields[2], prefix: "+") : nil
            } else if line.hasPrefix("+"), old != nil || new != nil {
                kind = .addition; newLine = new; new = new.map { $0 + 1 }
            } else if line.hasPrefix("-"), old != nil || new != nil {
                kind = .deletion; oldLine = old; old = old.map { $0 + 1 }
            } else if line.hasPrefix(" "), old != nil || new != nil {
                kind = .context; oldLine = old; newLine = new
                old = old.map { $0 + 1 }; new = new.map { $0 + 1 }
            }
            file.lines.append(PatchLine(id: index, text: line, kind: kind, old: oldLine, new: newLine))
        }
        if !file.lines.isEmpty { files.append(file) }
        return files
    }
    private static func location(_ field: Substring, prefix: Character) -> Int? {
        guard field.first == prefix else { return nil }
        return Int(field.dropFirst().split(separator: ",").first ?? "")
    }
}

/// Prefer the latest canonical turn patch over overlapping per-item patches.
public enum ChangeOverview {
    public static func paths(_ items: [Activity]) -> [String] {
        var paths = Set(items.flatMap { ($0.files ?? []).map(\.path) })
        if let latest = items.last(where: { $0.kind == "diff" }) {
            paths.formUnion(PatchDocument.parse(latest.text).map(\.path).filter { $0 != "Patch" })
        }
        return paths.sorted()
    }
    private static func fileCount(_ count: Int) -> String {
        count == 1 ? String(localized: "1 file changed", bundle: relayLocalizationBundle) : String(localized: "\(count) files changed", bundle: relayLocalizationBundle)
    }
    public static func describe(_ items: [Activity]) -> String {
        let files: [PatchFile]
        if let patch = items.last(where: { $0.kind == "diff" }) {
            files = PatchDocument.parse(patch.text)
        } else {
            var latest: [String: ChangedFile] = [:]
            for item in items { for file in item.files ?? [] { latest[file.path] = file } }
            guard !latest.isEmpty else { return "" }
            let count = fileCount(latest.count)
            guard latest.values.allSatisfy({ $0.patch?.contains("@@ ") == true }) else { return count }
            files = latest.values.flatMap { PatchDocument.parse($0.patch ?? "", path: $0.path) }
        }
        let count = Set(files.map(\.path)).count
        guard count > 0 else { return "" }
        return fileCount(count) + " · +\(files.reduce(0) { $0 + $1.additions }) −\(files.reduce(0) { $0 + $1.deletions })"
    }
}
