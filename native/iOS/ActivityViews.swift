import SwiftUI

/// Explicit destinations keep the aggregate, file list, and one operation distinct.
enum ActivityRoute: Hashable {
    case all, files, file(String), operation(String)
    var identity: String {
        switch self { case .all: "all"; case .files: "files"; case .file(let path): "file/" + path; case .operation(let id): "operation/" + id }
    }
}

struct ToolSummaryView: View {
    let group: TranscriptGroup
    let open: (ActivityRoute) -> Void
    @State private var expanded = false
    @State private var changeOverview = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var running: Int { group.items.filter { $0.state == "running" }.count }
    private var failed: Int { group.items.filter { $0.state == "failed" || $0.state == "declined" }.count }
    private var state: String { running > 0 ? "WORKING" : failed > 0 ? "FAILED" : group.items.allSatisfy { $0.state == "completed" } ? "READY" : "INACTIVE" }
    private var summary: String {
        var parts: [String] = []
        if group.commandCount > 0 { parts.append(group.commandCount == 1 ? String(localized: "1 command", bundle: relayLocalizationBundle) : String(localized: "\(group.commandCount) commands", bundle: relayLocalizationBundle)) }
        if group.toolCount > 0 { parts.append(group.toolCount == 1 ? String(localized: "1 operation", bundle: relayLocalizationBundle) : String(localized: "\(group.toolCount) operations", bundle: relayLocalizationBundle)) }
        if !changeOverview.isEmpty { parts.append(changeOverview) }
        if parts.isEmpty { parts.append(toolCount(group)) }
        if failed > 0 { parts.append(String(localized: "\(failed) failed", bundle: relayLocalizationBundle)) }
        return parts.joined(separator: " · ").replacingOccurrences(of: " −", with: "\u{00a0}−")
    }
    private var preview: Activity? {
        let operations = group.items.filter { $0.command != nil || $0.toolName != nil }
        return operations.last(where: { $0.state == "running" }) ?? operations.last
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { expanded.toggle() } } label: {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: toolIcon(group.kind)).foregroundStyle(.secondary).frame(width: 20)
                    Text(summary).font(.footnote.weight(.medium)).foregroundStyle(.secondary).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if state != "INACTIVE" { SessionStatusMark(status: state).font(.caption) }
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }.frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(RelayRowPressStyle()).accessibilityIdentifier("tool." + group.id)
                .accessibilityValue(expanded ? String(localized: "Details expanded", bundle: relayLocalizationBundle) : String(localized: "Details collapsed", bundle: relayLocalizationBundle))
            if expanded {
                if group.items.count > 5 {
                    Text(String(localized: "Latest activities", bundle: relayLocalizationBundle)).font(.caption2).foregroundStyle(.tertiary).padding(.leading, 30)
                }
                ForEach(Array(group.items.suffix(5))) { item in
                    Button { open(.operation(item.id)) } label: { ActivitySummaryRow(item: item) }
                        .buttonStyle(RelayRowPressStyle()).accessibilityIdentifier("activity.item." + item.id)
                }
                Button { open(.all) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "list.bullet").frame(width: 20)
                        Text(String(localized: "View all \(group.items.count) activities", bundle: relayLocalizationBundle))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right").font(.caption2)
                    }.font(.footnote).frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("tool.details." + group.id)
            } else {
                if let preview {
                    Button { open(.operation(preview.id)) } label: { ActivitySummaryRow(item: preview) }
                        .buttonStyle(RelayRowPressStyle()).accessibilityIdentifier("activity.preview." + preview.id)
                }
                if !group.changedPaths.isEmpty {
                    Button { open(group.changedPaths.count == 1 ? .file(group.changedPaths[0]) : .files) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "doc.text").frame(width: 20)
                            Text(group.changedPaths.prefix(2).map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", ") + (group.changedPaths.count > 2 ? " +\(group.changedPaths.count - 2)" : ""))
                                .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        }.font(.footnote).foregroundStyle(.secondary).frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(RelayRowPressStyle()).accessibilityIdentifier(group.changedPaths.count == 1 ? "activity.file." + group.changedPaths[0] : "activity.files." + group.id)
                }
            }
        }.padding(.horizontal, 12).padding(.vertical, 4)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            .task(id: group.items.filter { $0.kind == "diff" || $0.kind == "fileChange" }) {
                let items = group.items
                let summary = await Task.detached { ChangeOverview.describe(items) }.value
                if !Task.isCancelled { changeOverview = summary }
            }
    }
}

/// One shared alignment and bounded preview in the chat and aggregate list.
private struct ActivitySummaryRow: View {
    let item: Activity
    private var title: String {
        if let command = item.command { return ActivityPreview.command(command) }
        if item.toolName != nil { return ActivityPreview.tool(item) }
        let paths = ChangeOverview.paths([item])
        return paths.isEmpty ? item.kind : paths.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", ")
    }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: item.command != nil ? "terminal" : item.toolName != nil ? "wrench.and.screwdriver" : "doc.text")
                .foregroundStyle(.secondary).frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(item.command == nil ? .footnote : .footnote.monospaced()).lineLimit(2)
                if item.state == "running", let detail = ActivityPreview.detail(item), !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if item.state == "failed" || item.state == "declined" { Image(systemName: "exclamationmark.circle.fill").foregroundStyle(RelayPalette.failure).accessibilityLabel(activityState(item.state)) }
            else if item.state == "running" { Image(systemName: "clock").foregroundStyle(RelayPalette.working).accessibilityLabel(activityState(item.state)) }
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }.font(.caption2).foregroundStyle(.primary).padding(.vertical, 5)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
    }
}

struct ToolDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let group: TranscriptGroup
    var route: ActivityRoute = .all
    var body: some View {
        NavigationStack {
            ActivityDestinationView(group: group, route: route, close: { dismiss() })
        }
    }
}

private struct ActivityDestinationView: View {
    @Environment(RelayController.self) private var relay
    let group: TranscriptGroup
    let route: ActivityRoute
    let close: () -> Void
    private var liveGroup: TranscriptGroup { TranscriptGroup.make(relay.chat.items).first { $0.id == group.id } ?? group }
    private var title: String {
        switch route {
        case .all: String(localized: "Activity", bundle: relayLocalizationBundle)
        case .files: String(localized: "Changed files", bundle: relayLocalizationBundle)
        case .file(let path): URL(fileURLWithPath: path).lastPathComponent
        case .operation: String(localized: "Operation", bundle: relayLocalizationBundle)
        }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                switch route {
                case .all:
                    HStack(spacing: 12) {
                        Text(String(localized: "\(liveGroup.items.count) activities", bundle: relayLocalizationBundle))
                        Spacer()
                        let failed = liveGroup.items.filter { $0.state == "failed" || $0.state == "declined" }.count
                        if failed > 0 { Label(String(localized: "\(failed) failed", bundle: relayLocalizationBundle), systemImage: "exclamationmark.circle").foregroundStyle(RelayPalette.failure) }
                    }.font(.caption).foregroundStyle(.secondary).padding(.bottom, 8)
                    ForEach(liveGroup.items) { item in
                        NavigationLink { ActivityDestinationView(group: group, route: .operation(item.id), close: close) } label: { ActivitySummaryRow(item: item) }
                            .buttonStyle(RelayRowPressStyle()).accessibilityIdentifier("activity.aggregate." + item.id)
                    }
                case .files:
                    ForEach(liveGroup.changedPaths, id: \.self) { path in
                        NavigationLink { ActivityDestinationView(group: group, route: .file(path), close: close) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "doc.text").foregroundStyle(.secondary).frame(width: 20)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(URL(fileURLWithPath: path).lastPathComponent).font(.subheadline)
                                    Text(path).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                            }.frame(maxWidth: .infinity, minHeight: 44).padding(.vertical, 4).contentShape(Rectangle())
                        }.buttonStyle(RelayRowPressStyle()).accessibilityIdentifier("activity.path." + path)
                    }
                case .file(let path):
                    Text(path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    ForEach(liveGroup.items.filter { ChangeOverview.paths([$0]).contains(path) }.suffix(1)) { item in
                        if item.kind == "diff" { PatchView(patch: item.text, focusedPath: path, showHeader: false) }
                        else if let file = item.files?.first(where: { $0.path == path }) {
                            Text(fileChangeLabel(file.kind)).font(.caption).foregroundStyle(.secondary)
                            if let patch = file.patch, !patch.isEmpty {
                                if patch.contains("@@ ") { PatchView(patch: patch, path: path, showHeader: false) }
                                else { CodeBlockView(code: patch, language: URL(fileURLWithPath: path).pathExtension) }
                            } else { Text(String(localized: "No patch provided", bundle: relayLocalizationBundle)).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                case .operation(let id):
                    ForEach(liveGroup.items.filter { $0.id == id }) { item in
                        if item.kind == "diff" || item.kind == "fileChange" { FileActivityDetail(item: item) }
                        else { ActivityDetailRow(item: item, initiallyExpanded: true) }
                    }
                }
            }.padding(20)
        }.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(String(localized: "Close", bundle: relayLocalizationBundle), action: close) }
                if route == .all { ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button(String(localized: "Copy All Outputs", bundle: relayLocalizationBundle), systemImage: "doc.on.doc") {
                            UIPasteboard.general.string = liveGroup.items.map { $0.command != nil ? $0.commandOutput : $0.resultSummary ?? $0.text }.joined(separator: "\n\n")
                        }
                    } label: { Image(systemName: "doc.on.doc").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel(String(localized: "Copy Activity", bundle: relayLocalizationBundle))
                } }
            }
    }
}

private struct FileActivityDetail: View {
    let item: Activity
    @State private var expanded: Set<String> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var files: [ChangedFile] {
        if let files = item.files, !files.isEmpty { return files }
        return PatchDocument.parse(item.text).map { ChangedFile(path: $0.path, kind: "", previousPath: nil, patch: $0.lines.map(\.text).joined(separator: "\n")) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: RelaySpacing.compact) {
            ForEach(files, id: \.path) { file in
                VStack(alignment: .leading, spacing: RelaySpacing.compact) {
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                            if expanded.contains(file.path) { expanded.remove(file.path) } else { expanded.insert(file.path) }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.text").foregroundStyle(.secondary)
                            Text(URL(fileURLWithPath: file.path).lastPathComponent).font(.subheadline.weight(.medium)).lineLimit(2)
                            Spacer(minLength: 8)
                            if !file.kind.isEmpty { Text(fileChangeLabel(file.kind)).font(.caption).foregroundStyle(.secondary) }
                            Image(systemName: expanded.contains(file.path) ? "chevron.down" : "chevron.right").font(.caption2).foregroundStyle(.secondary)
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("file.detail." + file.path)
                    if expanded.contains(file.path) {
                        if let patch = file.patch, !patch.isEmpty {
                            if patch.contains("@@ ") { PatchView(patch: patch, path: file.path, showHeader: false) }
                            else { CodeBlockView(code: patch, language: URL(fileURLWithPath: file.path).pathExtension) }
                        } else { Text(String(localized: "No patch provided", bundle: relayLocalizationBundle)).font(.caption).foregroundStyle(.secondary) }
                    }
                }.contextMenu {
                    Button(String(localized: "Copy Path", bundle: relayLocalizationBundle), systemImage: "doc.on.doc") { UIPasteboard.general.string = file.path }
                    if let patch = file.patch { Button(String(localized: "Copy Patch", bundle: relayLocalizationBundle), systemImage: "doc.on.doc") { UIPasteboard.general.string = patch } }
                }
            }
        }.onAppear { if files.count == 1, let path = files.first?.path { expanded.insert(path) } }
    }
}

private struct ActivityDetailRow: View {
    let item: Activity
    @State private var expanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    init(item: Activity, initiallyExpanded: Bool) {
        self.item = item; _expanded = State(initialValue: initiallyExpanded)
    }
    private var output: String { item.command != nil ? item.commandOutput : item.resultSummary ?? (item.toolName == nil ? item.text : "") }
    private var status: String {
        switch item.state { case "running": "WORKING"; case "completed": "READY"; case "failed", "declined": "FAILED"; default: "INACTIVE" }
    }
    private var title: String {
        if item.kind == "diff" { return "Diff" }
        if let name = item.toolName { return name }
        if item.kind == "fileChange" { return String(localized: "File changes", bundle: relayLocalizationBundle) }
        return item.kind == "mcpToolCall" ? String(localized: "Tool", bundle: relayLocalizationBundle) : String(localized: "Command", bundle: relayLocalizationBundle)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: RelaySpacing.row) {
            HStack(spacing: RelaySpacing.compact) {
                if item.state != nil { SessionStatusMark(status: status).font(.caption) }
                Text(title).font(.subheadline.weight(.semibold))
                Spacer(minLength: 4)
                Text(activityState(item.state)).font(.caption).foregroundStyle(.secondary)
                Menu {
                    if let command = item.command { Button(String(localized: "Copy Command", bundle: relayLocalizationBundle), systemImage: "terminal") { UIPasteboard.general.string = command } }
                    Button(String(localized: "Copy Available Output", bundle: relayLocalizationBundle), systemImage: "doc.on.doc") { UIPasteboard.general.string = output }
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                    .accessibilityLabel(String(localized: "Output actions", bundle: relayLocalizationBundle))
            }
            if let server = item.toolServer { Text(server).font(.caption).foregroundStyle(.secondary) }
            if let command = item.command {
                ScrollView(.horizontal) {
                    CommandPreviewView(command: command).fixedSize(horizontal: true, vertical: false)
                }.contextMenu { Button(String(localized: "Copy Command", bundle: relayLocalizationBundle), systemImage: "doc.on.doc") { UIPasteboard.general.string = command } }
            }
            if item.exitCode != nil || item.durationMs != nil || item.truncated == true {
            HStack(spacing: RelaySpacing.row) {
                if let code = item.exitCode { Label("Exit \(code)", systemImage: code == 0 ? "checkmark.circle" : "exclamationmark.circle") }
                if let duration = item.durationMs { Text(String(format: "%.1f s", Double(duration) / 1000)) }
                if item.truncated == true { Text(String(localized: "Partial content", bundle: relayLocalizationBundle)) }
            }.font(.caption).foregroundStyle(.secondary)
            }
            if !expanded && !ChangeOverview.paths([item]).isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(ChangeOverview.paths([item]), id: \.self) { path in
                        HStack(alignment: .firstTextBaseline) {
                            Text(URL(fileURLWithPath: path).lastPathComponent).lineLimit(2)
                            Spacer(minLength: 8)
                            if let file = item.files?.first(where: { $0.path == path }) {
                                Text(fileChangeLabel(file.kind)).foregroundStyle(.secondary)
                            }
                        }.font(.caption).contextMenu {
                            Button(String(localized: "Copy Path", bundle: relayLocalizationBundle), systemImage: "doc.on.doc") { UIPasteboard.general.string = path }
                        }
                    }
                }
            }
            if let progress = item.progress, item.state == "running" {
                Text(progress).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack {
                    Image(systemName: "chevron.right").rotationEffect(.degrees(expanded ? 90 : 0))
                    Text(item.files?.isEmpty == false || item.kind == "diff" ? String(localized: "Changes", bundle: relayLocalizationBundle) : "Output")
                    Spacer()
                    if !output.isEmpty && item.files?.isEmpty != false && item.kind != "diff" { Text(output.split(separator: "\n", omittingEmptySubsequences: false).count == 1 ? String(localized: "1 line", bundle: relayLocalizationBundle) : String(localized: "\(output.split(separator: "\n", omittingEmptySubsequences: false).count) lines", bundle: relayLocalizationBundle)).foregroundStyle(.secondary) }
                }.font(.caption.weight(.medium)).frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("activity.output." + item.id)
                .accessibilityValue(expanded ? String(localized: "Expanded", bundle: relayLocalizationBundle) : String(localized: "Collapsed", bundle: relayLocalizationBundle))
            if expanded {
                outputContent.transition(.opacity)
            }
        }.animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: status)
            .onChange(of: item.state) { _, state in if state == "running" { expanded = true } }
    }
    @ViewBuilder private var outputContent: some View {
        if item.kind == "diff" { PatchView(patch: item.text) }
        else if let files = item.files, !files.isEmpty {
            ForEach(Array(files.enumerated()), id: \.element.path) { _, file in
                VStack(alignment: .leading, spacing: RelaySpacing.compact) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(URL(fileURLWithPath: file.path).lastPathComponent).font(.subheadline.weight(.medium)).lineLimit(2)
                        Spacer()
                        Text(fileChangeLabel(file.kind)).font(.caption).foregroundStyle(.secondary).fixedSize()
                    }.contextMenu {
                        Button(String(localized: "Copy Path", bundle: relayLocalizationBundle), systemImage: "doc.on.doc") { UIPasteboard.general.string = file.path }
                        if let previous = file.previousPath { Button(String(localized: "Copy Previous Path", bundle: relayLocalizationBundle)) { UIPasteboard.general.string = previous } }
                    }
                    if let patch = file.patch, !patch.isEmpty {
                        if patch.hasPrefix("diff --git ") || patch.hasPrefix("@@ ") || patch.contains("\n@@ ") { PatchView(patch: patch, path: file.path) }
                        else { CodeBlockView(code: patch, language: URL(fileURLWithPath: file.path).pathExtension) }
                    }
                }
            }
        } else if item.kind == "commandExecution" || item.kind == "command_output" {
            if output.isEmpty { Text(item.state == "running" ? String(localized: "Waiting for output…", bundle: relayLocalizationBundle) : String(localized: "No output", bundle: relayLocalizationBundle)).font(.caption).foregroundStyle(.secondary) }
            else if #available(iOS 18.0, *) {
                TerminalOutputView(text: output).accessibilityIdentifier("activity." + item.kind + "." + item.id)
            } else { CodeBlockView(code: output, language: "output") }
        } else if let result = item.resultSummary {
            ChatMarkdown(text: result, identifier: "activity." + item.kind + "." + item.id)
        } else if item.toolName == nil {
            Text(output).font(.callout).textSelection(.enabled)
        } else {
            Text(item.state == "running" ? String(localized: "Waiting for tool result…", bundle: relayLocalizationBundle) : String(localized: "No text result provided", bundle: relayLocalizationBundle))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private func toolTitle(_ kind: TranscriptGroup.Kind) -> String {
    switch kind { case .terminal: String(localized: "Terminal", bundle: relayLocalizationBundle); case .mcp: "MCP"; case .changes: String(localized: "Changes", bundle: relayLocalizationBundle); default: String(localized: "Activity", bundle: relayLocalizationBundle) }
}
private func toolIcon(_ kind: TranscriptGroup.Kind) -> String {
    switch kind { case .terminal: "terminal"; case .mcp: "wrench.and.screwdriver"; case .changes: "doc.text"; default: "list.bullet" }
}
private func toolCount(_ group: TranscriptGroup) -> String {
    let count = group.items.count
    switch group.kind {
    case .terminal: return count == 1 ? String(localized: "1 command", bundle: relayLocalizationBundle) : String(localized: "\(count) commands", bundle: relayLocalizationBundle)
    case .mcp: return count == 1 ? String(localized: "1 operation", bundle: relayLocalizationBundle) : String(localized: "\(count) operations", bundle: relayLocalizationBundle)
    case .changes: return count == 1 ? String(localized: "1 event", bundle: relayLocalizationBundle) : String(localized: "\(count) events", bundle: relayLocalizationBundle)
    default: return count == 1 ? String(localized: "1 item", bundle: relayLocalizationBundle) : String(localized: "\(count) items", bundle: relayLocalizationBundle)
    }
}

private func activityState(_ state: String?) -> String {
    switch state { case "running": String(localized: "Working", bundle: relayLocalizationBundle); case "completed": String(localized: "Completed", bundle: relayLocalizationBundle); case "failed": String(localized: "Failed", bundle: relayLocalizationBundle); case "declined": String(localized: "Declined", bundle: relayLocalizationBundle); default: "" }
}

private func fileChangeLabel(_ kind: String) -> String {
    switch kind { case "add", "create": String(localized: "Created", bundle: relayLocalizationBundle); case "delete": String(localized: "Deleted", bundle: relayLocalizationBundle); case "rename", "move": String(localized: "Renamed", bundle: relayLocalizationBundle); default: String(localized: "Modified", bundle: relayLocalizationBundle) }
}
