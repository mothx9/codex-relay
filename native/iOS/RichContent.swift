import SwiftUI

private struct MarkdownProseFontKey: EnvironmentKey { static let defaultValue: Font = .body }
extension EnvironmentValues {
    var markdownProseFont: Font {
        get { self[MarkdownProseFontKey.self] }
        set { self[MarkdownProseFontKey.self] = newValue }
    }
}
private struct CompleteMessageKey: EnvironmentKey {
    static let defaultValue: String? = nil
}
extension EnvironmentValues {
    var completeMessage: String? {
        get { self[CompleteMessageKey.self] }
        set { self[CompleteMessageKey.self] = newValue }
    }
}

struct ChatMarkdown: View {
    let text: String
    let identifier: String
    var compact = false
    @State private var rendering = MarkdownRendering()
    private var blocks: [RichBlock] { rendering.blocks }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if blocks.isEmpty {
                Text(text).font(.body).fixedSize(horizontal: false, vertical: true).textSelection(.enabled).accessibilityIdentifier(identifier)
            } else {
                ForEach(blocks) { block in
                    MarkdownBlockView(block: block, identifier: block.id == "0" ? identifier : identifier + "." + block.id)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.markdownProseFont, compact ? .callout : .body)
            .onChange(of: text, initial: true) { _, value in rendering.submit(value) }
            .onDisappear { rendering.cancel() }
    }
}

/// One parse at a time per visible message; a short throttle coalesces deltas
/// without waiting for the stream to become quiet. Stable parser block IDs keep
/// selection, code scrollers and disclosure state in place across updates.
@MainActor @Observable
private final class MarkdownRendering {
    private(set) var blocks: [RichBlock] = []
    @ObservationIgnored private var latest = ""
    @ObservationIgnored private var rendered: String?
    @ObservationIgnored private var worker: Task<Void, Never>?
    func submit(_ text: String) {
        latest = text
        guard worker == nil, rendered != latest else { return }
        worker = Task {
            while !Task.isCancelled, rendered != latest {
                let source = latest
                let parsed = await Task.detached(priority: .userInitiated) { RichDocument.parse(source) }.value
                guard !Task.isCancelled else { return }
                blocks = parsed; rendered = source
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            }
            worker = nil
        }
    }
    func cancel() { worker?.cancel(); worker = nil }
}

private struct MarkdownBlockView: View {
    @Environment(\.completeMessage) private var completeMessage
    @Environment(\.markdownProseFont) private var baseFont
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
                            Text(block.ordinal.map { "\($0 + index)." } ?? "•").font(.body.monospacedDigit()).foregroundStyle(.secondary).frame(minWidth: 18, alignment: .trailing)
                            MarkdownBlockView(block: child, identifier: identifier + "." + child.id)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.fixedSize(horizontal: false, vertical: true)
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
        Text(styled(spans)).lineSpacing(3).lineLimit(nil).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            .contextMenu {
                if let completeMessage {
                    Button(String(localized: "Copy Full Message", bundle: relayLocalizationBundle), systemImage: "doc.on.doc") { UIPasteboard.general.string = completeMessage }
                }
                Button(String(localized: "Copy Paragraph", bundle: relayLocalizationBundle), systemImage: "text.alignleft") { UIPasteboard.general.string = spans.map(\.text).joined() }
                ForEach(Array(Set(spans.compactMap(\.link))).sorted(), id: \.self) { destination in
                    if let url = RichDocument.webURL(destination) {
                        Menu(destination) {
                            Link(String(localized: "Open Link", bundle: relayLocalizationBundle), destination: url)
                            Button(String(localized: "Copy Link", bundle: relayLocalizationBundle), systemImage: "link") { UIPasteboard.general.url = url }
                        }
                    }
                }
            }
    }
    private var proseFont: Font {
        guard block.kind == .heading else { return baseFont }
        return block.level == 1 ? .title3.weight(.semibold) : .headline
    }
    private func styled(_ spans: [RichSpan]) -> AttributedString {
        var result = AttributedString()
        for span in spans {
            var part = AttributedString(span.text)
            var font: Font = span.code ? .system(.callout, design: .monospaced) : proseFont
            if span.bold { font = font.bold() }; if span.italic { font = font.italic() }
            // Leave ordinary prose font to the block so headings can scale.
            part.font = font
            if span.code { part.backgroundColor = Color.primary.opacity(0.07) }
            if span.strikethrough { part.strikethroughStyle = .single }
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
        case .comment, .shellOperator: .secondary
        case .command: Color.accentColor
        case .variable: Color(uiColor: .systemOrange)
        case .keyword, .directive, .flag: Color(uiColor: .systemIndigo)
        case .string: Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? .systemMint : UIColor(red: 0.04, green: 0.38, blue: 0.25, alpha: 1) })
        case .number: Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? .systemOrange : UIColor(red: 0.62, green: 0.25, blue: 0.02, alpha: 1) })
        }
    }
}

struct CodeBlockView: View {
    @Environment(\.completeMessage) private var completeMessage
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
                Text(language?.isEmpty == false ? language! : String(localized: "Code", bundle: relayLocalizationBundle)).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                Button { UIPasteboard.general.string = code } label: { Image(systemName: "doc.on.doc").frame(minWidth: 44, minHeight: 44) }
                    .buttonStyle(.plain).accessibilityLabel(String(localized: "Copy Code", bundle: relayLocalizationBundle))
            }.padding(.leading, RelaySpacing.row)
            Divider()
            ScrollView(.horizontal) {
                Text(tokens.isEmpty ? AttributedString(code) : highlighted).font(.footnote.monospaced())
                    .fixedSize(horizontal: true, vertical: false).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(RelaySpacing.row)
            }
        }.background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            .contextMenu {
                Button(String(localized: "Copy Code", bundle: relayLocalizationBundle), systemImage: "doc.on.doc") { UIPasteboard.general.string = code }
                if let completeMessage { Button(String(localized: "Copy Full Message", bundle: relayLocalizationBundle), systemImage: "text.alignleft") { UIPasteboard.general.string = completeMessage } }
            }
            .task(id: code + (language ?? "")) {
                let source = code; let syntax = language
                let parsed = await Task.detached(priority: .userInitiated) { CodeTokens.tokenize(source, language: syntax) }.value
                if !Task.isCancelled { tokens = parsed }
            }
    }
}

struct PatchView: View {
    let patch: String
    var path = "Patch"
    var focusedPath: String? = nil
    var showHeader = true
    @State private var files: [PatchFile] = []
    var body: some View {
        VStack(alignment: .leading, spacing: RelaySpacing.page) {
            ForEach(files.filter { focusedPath == nil || $0.path == focusedPath }) { file in
                VStack(alignment: .leading, spacing: RelaySpacing.row) {
                    if showHeader {
                    HStack {
                        Text(URL(fileURLWithPath: file.path).lastPathComponent).font(.subheadline.weight(.semibold)).lineLimit(2)
                        Spacer()
                        Text("+\(file.additions) −\(file.deletions)").font(.caption.monospacedDigit())
                        Menu {
                            Button(String(localized: "Copy Path", bundle: relayLocalizationBundle), systemImage: "doc.on.doc") { UIPasteboard.general.string = file.path }
                            Button(String(localized: "Copy Patch", bundle: relayLocalizationBundle), systemImage: "doc.on.doc") { UIPasteboard.general.string = patch }
                        } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                            .accessibilityLabel(String(localized: "Actions for ", bundle: relayLocalizationBundle) + file.path)
                    }
                    }
                    ScrollView(.horizontal) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(file.lines.filter { $0.kind != .metadata }) { line in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(line.old.map(String.init) ?? "").frame(width: 32, alignment: .trailing).foregroundStyle(.tertiary)
                                    Text(line.new.map(String.init) ?? "").frame(width: 32, alignment: .trailing).foregroundStyle(.tertiary)
                                    Text(line.text).textSelection(.enabled)
                                    Spacer(minLength: 0)
                                }.font(.caption.monospaced()).fixedSize(horizontal: false, vertical: true)
                                    .padding(.horizontal, 8).padding(.vertical, 2)
                                    .background { Rectangle().fill(tint(line.kind)) }
                            }
                        }.fixedSize(horizontal: true, vertical: false)
                    }.background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }.task(id: patch + path) {
            let source = patch, filename = path
            let parsed = await Task.detached { PatchDocument.parse(source, path: filename) }.value
            if !Task.isCancelled { files = parsed }
        }.contextMenu { Button(String(localized: "Copy Patch", bundle: relayLocalizationBundle), systemImage: "doc.on.doc") { UIPasteboard.general.string = patch } }
    }
    private func tint(_ kind: PatchLine.Kind) -> Color {
        switch kind {
        case .addition: RelayPalette.addition.opacity(0.08)
        case .deletion: RelayPalette.deletion.opacity(0.08)
        case .hunk: Color.primary.opacity(0.04)
        default: .clear
        }
    }
}

@available(iOS 18.0, *)
struct TerminalOutputView: View {
    let text: String
    @State private var following = true
    @State private var unseen = false
    @ScaledMetric(relativeTo: .caption) private var maximumHeight: CGFloat = 300
    private var chunks: [String] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return stride(from: 0, to: lines.count, by: 48).map { lines[$0..<min($0 + 48, lines.count)].joined(separator: "\n") }
    }
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(chunks.enumerated()), id: \.offset) { _, chunk in
                        Text(chunk).font(.caption.monospaced()).textSelection(.enabled)
                            .fixedSize(horizontal: true, vertical: true)
                            .contextMenu { Button(String(localized: "Copy Available Output", bundle: relayLocalizationBundle), systemImage: "doc.on.doc") { UIPasteboard.general.string = text } }
                    }
                    Color.clear.frame(height: 1).id("output.latest")
                }.padding(10)
            }.frame(height: min(maximumHeight, max(56, CGFloat(text.filter { $0 == "\n" }.count + 1) * 18 + 20)))
                .defaultScrollAnchor(.bottomLeading, for: .initialOffset)
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.visibleRect.maxY >= geometry.contentSize.height - 60
                } action: { _, atBottom in
                    following = atBottom
                    if atBottom { unseen = false }
                }
                .onChange(of: text) { _, _ in
                    if following { proxy.scrollTo("output.latest", anchor: .bottomLeading) }
                    else { unseen = true }
                }
                .overlay(alignment: .bottomTrailing) {
                    if unseen {
                        Button { proxy.scrollTo("output.latest", anchor: .bottomLeading); following = true; unseen = false } label: {
                            Label(String(localized: "Latest output", bundle: relayLocalizationBundle), systemImage: "arrow.down")
                        }.font(.caption).buttonStyle(.borderedProminent).padding(8)
                    }
                }
        }.background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            .contextMenu { Button(String(localized: "Copy Output", bundle: relayLocalizationBundle), systemImage: "doc.on.doc") { UIPasteboard.general.string = text } }
    }
}

struct CommandPreviewView: View {
    let command: String
    @State private var highlighted = AttributedString()
    var body: some View {
        Text(highlighted.characters.isEmpty ? AttributedString(command) : highlighted)
            .font(.caption.monospaced()).textSelection(.enabled)
            .task(id: command) {
                let source = command
                let tokens = await Task.detached { ShellTokens.tokenize(source) }.value
                guard !Task.isCancelled else { return }
                var value = AttributedString()
                for token in tokens {
                    var part = AttributedString(token.text)
                    part.foregroundColor = CodePalette.color(token.kind)
                    value.append(part)
                }
                highlighted = value
            }
    }
}
