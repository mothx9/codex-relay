import Foundation
import Markdown

public struct RichSpan: Equatable, Sendable {
    public var text: String
    public var bold = false
    public var italic = false
    public var code = false
    public var link: String?
}
public struct RichBlock: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case paragraph, heading, code, quote, list, item, table, row, cell, rule }
    public let id: String
    public var kind: Kind
    public var spans: [RichSpan] = []
    public var children: [RichBlock] = []
    public var text = ""
    public var language: String?
    public var level = 0
    public var ordinal: Int?
}
public enum RichDocument {
    /// GFM parsing is provided by swift-markdown/cmark, including incomplete
    /// streaming constructs. No network, HTML rendering or executable markup.
    public static func parse(_ source: String) -> [RichBlock] {
        let document = Document(parsing: source)
        return document.children.enumerated().map { block($0.element, id: String($0.offset)) }
    }
    public static func webURL(_ value: String) -> URL? {
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased(),
              ["https", "http", "mailto"].contains(scheme),
              scheme == "mailto" || !(url.host ?? "").isEmpty else { return nil }
        return url
    }
    private static func block(_ node: any Markup, id: String) -> RichBlock {
        var result = RichBlock(id: id, kind: .paragraph)
        switch node {
        case let code as CodeBlock:
            result.kind = .code; result.text = code.code; result.language = code.language
        case let heading as Heading:
            result.kind = .heading; result.level = heading.level; result.spans = inline(node)
        case is Paragraph: result.spans = inline(node)
        case is BlockQuote: result.kind = .quote
        case let list as OrderedList: result.kind = .list; result.ordinal = Int(list.startIndex)
        case is UnorderedList: result.kind = .list
        case is ListItem: result.kind = .item
        case is Table: result.kind = .table
        case is Table.Head, is Table.Row: result.kind = .row
        case is Table.Cell: result.kind = .cell; result.spans = inline(node)
        case is ThematicBreak: result.kind = .rule
        default:
            result.spans = inline(node)
        }
        if [.quote, .list, .item, .table, .row].contains(result.kind) {
            // Table.Body is a structural container; rows share one grid.
            let nodes = node.children.flatMap { child -> [any Markup] in child is Table.Body ? Array(child.children) : [child] }
            result.children = nodes.enumerated().map { block($0.element, id: id + "." + String($0.offset)) }
        }
        return result
    }
    private static func inline(_ node: any Markup, bold: Bool = false, italic: Bool = false, link: String? = nil) -> [RichSpan] {
        if let text = node as? Markdown.Text {
            guard link == nil, let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [RichSpan(text: text.string, bold: bold, italic: italic, link: link)] }
            let source = text.string; var spans: [RichSpan] = []; var cursor = source.startIndex
            for match in detector.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                guard let range = Range(match.range, in: source), let url = match.url,
                      ["https://", "http://", "mailto:"].contains(where: { source[range].lowercased().hasPrefix($0) }), webURL(url.absoluteString) != nil else { continue }
                if cursor < range.lowerBound { spans.append(RichSpan(text: String(source[cursor..<range.lowerBound]), bold: bold, italic: italic)) }
                spans.append(RichSpan(text: String(source[range]), bold: bold, italic: italic, link: url.absoluteString))
                cursor = range.upperBound
            }
            if cursor < source.endIndex { spans.append(RichSpan(text: String(source[cursor...]), bold: bold, italic: italic)) }
            return spans
        }
        if let code = node as? InlineCode { return [RichSpan(text: code.code, bold: bold, italic: italic, code: true, link: link)] }
        if node is SoftBreak { return [RichSpan(text: " ")] }
        if node is LineBreak { return [RichSpan(text: "\n")] }
        if let html = node as? InlineHTML { return [RichSpan(text: html.rawHTML)] }
        let destination = (node as? Markdown.Link)?.destination.flatMap { webURL($0)?.absoluteString } ?? link
        return node.children.flatMap { inline($0, bold: bold || node is Strong, italic: italic || node is Emphasis, link: destination) }
    }
}
