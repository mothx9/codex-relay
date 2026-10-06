import SwiftUI

struct ChatMarkdown: View {
    let text: String
    let identifier: String
    @State private var blocks: [RichBlock] = []
    var body: some View {
        VStack(alignment: .leading, spacing: RelaySpacing.row) {
            if blocks.isEmpty {
                Text(text).font(.body).textSelection(.enabled).accessibilityIdentifier(identifier)
            } else {
                ForEach(blocks) { block in
                    MarkdownBlockView(block: block, identifier: block.id == "0" ? identifier : identifier + "." + block.id)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .task(id: text) {
                let source = text
                let parsed = await Task.detached(priority: .userInitiated) { RichDocument.parse(source) }.value
                if !Task.isCancelled { blocks = parsed }
            }
    }
}

private struct MarkdownBlockView: View {
    let block: RichBlock
    let identifier: String
    var body: some View {
        Group {
            switch block.kind {
            case .paragraph, .cell:
                inline(block.spans).font(.body)
            case .heading:
                inline(block.spans).font(block.level == 1 ? .title3.bold() : .headline).accessibilityAddTraits(.isHeader)
            case .code:
                CodeBlockView(code: block.text, language: block.language)
            case .quote:
                HStack(alignment: .top, spacing: RelaySpacing.row) {
                    RoundedRectangle(cornerRadius: 2).fill(.tertiary).frame(width: 3)
                    children
                }.fixedSize(horizontal: false, vertical: true).foregroundStyle(.secondary)
            case .list:
                VStack(alignment: .leading, spacing: RelaySpacing.compact) {
                    ForEach(Array(block.children.enumerated()), id: \.element.id) { index, child in
                        HStack(alignment: .firstTextBaseline, spacing: RelaySpacing.row) {
                            Text(block.ordinal.map { "\($0 + index)." } ?? "•").font(.body.monospacedDigit()).foregroundStyle(.secondary)
                            MarkdownBlockView(block: child, identifier: identifier + "." + child.id)
                        }
                    }
                }
            case .item: children
            case .table:
                ScrollView(.horizontal) {
                    Grid(alignment: .topLeading, horizontalSpacing: RelaySpacing.page, verticalSpacing: RelaySpacing.row) {
                        ForEach(Array(block.children.enumerated()), id: \.element.id) { index, row in
                            GridRow {
                                ForEach(row.children) { cell in
                                    Text(styled(cell.spans)).font(index == 0 ? .body.bold() : .body)
                                        .frame(minWidth: 100, maxWidth: 260, alignment: .leading).textSelection(.enabled)
                                }
                            }
                            if index == 0 { Divider().gridCellUnsizedAxes(.horizontal) }
                        }
                    }.padding(RelaySpacing.row)
                }.background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            case .row: children
            case .rule: Divider()
            }
        }.accessibilityIdentifier(identifier)
    }
    private var children: some View {
        VStack(alignment: .leading, spacing: RelaySpacing.compact) {
            ForEach(block.children) { MarkdownBlockView(block: $0, identifier: identifier + "." + $0.id) }
        }
    }
    private func inline(_ spans: [RichSpan]) -> some View {
        Text(styled(spans)).textSelection(.enabled)
            .contextMenu {
                Button("Copia testo", systemImage: "doc.on.doc") { UIPasteboard.general.string = spans.map(\.text).joined() }
                ForEach(Array(Set(spans.compactMap(\.link))).sorted(), id: \.self) { destination in
                    if let url = RichDocument.webURL(destination) {
                        Menu(destination) {
                            Link("Apri link", destination: url)
                            Button("Copia link", systemImage: "link") { UIPasteboard.general.url = url }
                        }
                    }
                }
            }
    }
    private func styled(_ spans: [RichSpan]) -> AttributedString {
        var result = AttributedString()
        for span in spans {
            var part = AttributedString(span.text)
            var font: Font = span.code ? .system(.body, design: .monospaced) : .body
            if span.bold { font = font.bold() }; if span.italic { font = font.italic() }
            // Leave ordinary prose font to the block so headings can scale.
            if span.code || span.bold || span.italic { part.font = font }
            if let target = span.link, let url = RichDocument.webURL(target) { part.link = url; part.foregroundColor = .accentColor }
            result.append(part)
        }
        return result
    }
}

enum CodePalette {
    static func color(_ kind: CodeToken.Kind) -> Color {
        switch kind {
        case .plain: .primary
        case .comment: .secondary
        case .keyword, .directive: Color(uiColor: .systemIndigo)
        case .string: Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? .systemMint : UIColor(red: 0.04, green: 0.38, blue: 0.25, alpha: 1) })
        case .number: Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? .systemOrange : UIColor(red: 0.62, green: 0.25, blue: 0.02, alpha: 1) })
        }
    }
}

struct CodeBlockView: View {
    let code: String
    let language: String?
    @State private var tokens: [CodeToken] = []
    private var highlighted: AttributedString {
        var result = AttributedString()
        for token in tokens {
            var part = AttributedString(token.text); part.foregroundColor = CodePalette.color(token.kind); result.append(part)
        }
        return result
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language?.isEmpty == false ? language! : "Codice").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                Button { UIPasteboard.general.string = code } label: { Image(systemName: "doc.on.doc").frame(minWidth: 44, minHeight: 44) }
                    .buttonStyle(.plain).accessibilityLabel("Copia codice")
            }.padding(.leading, RelaySpacing.row)
            Divider()
            ScrollView(.horizontal) {
                Text(tokens.isEmpty ? AttributedString(code) : highlighted).font(.callout.monospaced())
                    .fixedSize(horizontal: true, vertical: false).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(RelaySpacing.row)
            }
        }.background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            .contextMenu { Button("Copia codice", systemImage: "doc.on.doc") { UIPasteboard.general.string = code } }
            .task(id: code + (language ?? "")) {
                let source = code; let syntax = language
                let parsed = await Task.detached(priority: .userInitiated) { CodeTokens.tokenize(source, language: syntax) }.value
                if !Task.isCancelled { tokens = parsed }
            }
    }
}
