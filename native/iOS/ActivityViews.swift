import SwiftUI

struct ToolSummaryView: View {
    let group: TranscriptGroup
    let open: (String?) -> Void
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var running: Int { group.items.filter { $0.state == "running" }.count }
    private var failed: Int { group.items.filter { $0.state == "failed" || $0.state == "declined" }.count }
    private var current: Activity? { group.items.last(where: { $0.state == "running" }) ?? group.items.last }
    private var state: String { running > 0 ? "WORKING" : failed > 0 ? "FAILED" : group.items.allSatisfy { $0.state == "completed" } ? "READY" : "INACTIVE" }
    private var tint: Color { if group.kind == .activity { return .secondary }; return group.kind == .terminal ? RelayPalette.terminal : group.kind == .mcp ? RelayPalette.tool : RelayPalette.file }
    @State private var changeOverview = ""
    private var summary: String {
        if group.kind == .activity {
            var parts: [String] = []
            if group.commandCount > 0 { parts.append(group.commandCount == 1 ? String(localized: "1 command", bundle: relayLocalizationBundle) : String(localized: "\(group.commandCount) commands", bundle: relayLocalizationBundle)) }
            if group.toolCount > 0 { parts.append(group.toolCount == 1 ? String(localized: "1 operation", bundle: relayLocalizationBundle) : String(localized: "\(group.toolCount) operations", bundle: relayLocalizationBundle)) }
            if !changeOverview.isEmpty { parts.append(changeOverview) }
            if running > 0 { parts.append(String(localized: "\(running) running", bundle: relayLocalizationBundle)) }
            if failed > 0 { parts.append(String(localized: "\(failed) failed", bundle: relayLocalizationBundle)) }
            return parts.joined(separator: " · ")
        }
        var value = group.kind == .changes && !changeOverview.isEmpty ? changeOverview : toolCount(group)
        if running > 0 { value += " · " + String(localized: "\(running) running", bundle: relayLocalizationBundle) }
        if failed > 0 { value += " · " + String(localized: "\(failed) failed", bundle: relayLocalizationBundle) }
        if state == "READY" { value += " · " + String(localized: "Completed", bundle: relayLocalizationBundle) }
        return value
    }
    private var command: Activity? {
        group.items.last(where: { $0.command != nil && $0.state == "running" }) ?? group.items.last(where: { $0.command != nil })
    }
    private var tool: Activity? {
        group.items.last(where: { $0.toolName != nil && $0.state == "running" }) ?? group.items.last(where: { $0.toolName != nil })
    }
    private func operationPreview(_ item: Activity, icon: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon).frame(width: 16).foregroundStyle(.secondary)
            Text(text).font(item.command == nil ? .caption : .caption.monospaced()).lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if item.state == "running" || item.state == "failed" || item.state == "declined" {
                Image(systemName: item.state == "running" ? "clock" : "exclamationmark.circle")
                    .foregroundStyle(item.state == "running" ? RelayPalette.working : RelayPalette.failure)
                    .accessibilityLabel(activityState(item.state))
            }
        }.font(.caption).foregroundStyle(.secondary)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: RelaySpacing.row) {
            Button { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { expanded.toggle() } } label: {
                VStack(alignment: .leading, spacing: RelaySpacing.compact) {
                    HStack(spacing: 10) {
                        Image(systemName: toolIcon(group.kind)).font(.subheadline.weight(.medium)).foregroundStyle(tint)
                            .frame(width: 24, height: 24)
                        Text(group.kind == .activity ? summary : toolTitle(group.kind)).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        if state != "INACTIVE" { SessionStatusMark(status: state).font(.caption) }
                        Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                    }
                    if group.kind != .activity { Text(summary).font(.caption).foregroundStyle(.secondary).padding(.leading, 24)
                        .contentTransition(.opacity)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: state) }

                }.foregroundStyle(.primary).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(RelayRowPressStyle()).accessibilityIdentifier("tool." + group.id)
                .accessibilityValue(expanded ? String(localized: "Details expanded", bundle: relayLocalizationBundle) : String(localized: "Details collapsed", bundle: relayLocalizationBundle))
            if !expanded {
                VStack(alignment: .leading, spacing: 8) {
                    if let command { operationPreview(command, icon: "terminal", text: ActivityPreview.command(command.command ?? "")) }
                    if let tool { operationPreview(tool, icon: "wrench.and.screwdriver", text: [tool.toolServer, tool.toolName].compactMap { $0 }.joined(separator: ".")) }
                    if !group.changedPaths.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "doc.text").frame(width: 16, height: 44)
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(group.changedPaths.prefix(3), id: \.self) { path in
                                    Button { open(path) } label: {
                                        HStack { Text(URL(fileURLWithPath: path).lastPathComponent).lineLimit(2); Spacer(); Image(systemName: "chevron.right").font(.caption2) }.frame(minHeight: 44).contentShape(Rectangle())
                                    }.buttonStyle(.plain).accessibilityIdentifier("activity.file." + path)
                                }
                                if group.changedPaths.count > 3 { Text("+\(group.changedPaths.count - 3)") }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.leading, 24)
            }
            if expanded, running > 0, let progress = current?.progress, !progress.isEmpty {
                Text(progress).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("tool.progress." + group.id)
            }
            if !expanded, running > 0, group.kind == .terminal, let item = current, !item.commandOutput.isEmpty {
                // A bounded tail is a live preview, not another scrolling terminal.
                Text(item.commandOutput.suffix(600).split(separator: "\n", omittingEmptySubsequences: false).suffix(1).joined(separator: "\n"))
                    .font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 10).overlay(alignment: .leading) { Capsule().fill(tint.opacity(0.4)).frame(width: 2) }
                    .accessibilityIdentifier("tool.live." + group.id)
            }
            if expanded {
                VStack(alignment: .leading, spacing: RelaySpacing.row) {
                    ForEach(Array(group.items.suffix(3))) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: item.command != nil ? "terminal" : item.toolName != nil ? "wrench.and.screwdriver" : "doc.text")
                                    .foregroundStyle(.secondary)
                                Text(item.command.map(ActivityPreview.command) ?? item.toolName ?? ChangeOverview.paths([item]).map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", "))
                                    .font(item.command == nil ? .caption : .caption.monospaced())
                                    .lineLimit(4).frame(maxWidth: .infinity, alignment: .leading)
                                if item.state != nil { SessionStatusMark(status: item.state == "running" ? "WORKING" : item.state == "failed" ? "FAILED" : item.state == "completed" ? "READY" : "INACTIVE") }
                            }.font(.caption)
                            if item.command != nil, !item.commandOutput.isEmpty {
                                Text(item.commandOutput.suffix(360).split(separator: "\n", omittingEmptySubsequences: false).suffix(3).joined(separator: "\n"))
                                    .font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(3)
                            }
                        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                    }
                    Button { open(nil) } label: {
                        HStack {
                            Text(String(localized: "Open details and output", bundle: relayLocalizationBundle))
                            Spacer()
                            Image(systemName: "arrow.up.right")
                        }.font(.caption.weight(.semibold)).frame(minHeight: 44)
                    }.accessibilityIdentifier("tool.details." + group.id)
                }.transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }.padding(.vertical, RelaySpacing.compact)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: state)
            .task(id: group.items.filter { $0.kind == "diff" || $0.kind == "fileChange" }) {
                let items = group.items
                let summary = await Task.detached { ChangeOverview.describe(items) }.value
                if !Task.isCancelled { changeOverview = summary }
            }
    }
}

struct ToolDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RelayController.self) private var relay
    let group: TranscriptGroup
    var focusedPath: String? = nil
    private var liveGroup: TranscriptGroup { TranscriptGroup.make(relay.chat.items).first { $0.id == group.id } ?? group }
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: RelaySpacing.row) {
                    HStack {
                        Label(focusedPath ?? (liveGroup.kind == .changes ? ChangeOverview.describe(liveGroup.items) : toolCount(liveGroup)), systemImage: focusedPath == nil ? toolIcon(group.kind) : "doc.text")
                        Spacer()
                        let running = liveGroup.items.filter { $0.state == "running" }.count
                        if focusedPath == nil && running > 0 { Text(String(localized: "\(running) running", bundle: relayLocalizationBundle)).foregroundStyle(RelayPalette.working) }
                    }.font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    if focusedPath == nil && liveGroup.commandCount > 0 {
                        let completed = liveGroup.items.filter { $0.state == "completed" }.count
                        let failed = liveGroup.items.filter { $0.state == "failed" || $0.state == "declined" }.count
                        HStack(spacing: RelaySpacing.page) {
                            if completed > 0 { Label(String(localized: "\(completed) completed", bundle: relayLocalizationBundle), systemImage: "checkmark.circle") }
                            if failed > 0 { Label(String(localized: "\(failed) failed", bundle: relayLocalizationBundle), systemImage: "xmark.circle").foregroundStyle(RelayPalette.failure) }
                        }.font(.caption).foregroundStyle(.secondary)
                    }
                    if let focusedPath {
                        ForEach(liveGroup.items.filter { ChangeOverview.paths([$0]).contains(focusedPath) }.suffix(1)) { item in
                            if item.kind == "diff" { PatchView(patch: item.text, focusedPath: focusedPath) }
                            else if let file = item.files?.first(where: { $0.path == focusedPath }) {
                                if let patch = file.patch { PatchView(patch: patch, path: file.path) }
                                else { Label(URL(fileURLWithPath: file.path).lastPathComponent, systemImage: "doc.text"); Text(fileChangeLabel(file.kind)).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    } else if liveGroup.kind == .changes {
                        ForEach(liveGroup.items) { item in
                            if item.kind == "diff" { PatchView(patch: item.text) }
                            else { FileActivityDetail(item: item) }
                        }
                    } else {
                    ForEach(liveGroup.items) { item in
                        if item.kind == "fileChange" || item.kind == "diff" { FileActivityDetail(item: item).id(item.id) }
                        else { ActivityDetailRow(item: item, initiallyExpanded: item.state == "running" || item.id == liveGroup.items.last?.id).id(item.id) }
                        if item.id != liveGroup.items.last?.id { Divider() }
                    }
                    }
                }.padding(RelaySpacing.page)
            }.onAppear {
                if liveGroup.items.count > 3, let target = liveGroup.items.first(where: { $0.state == "running" })?.id {
                    DispatchQueue.main.async { proxy.scrollTo(target, anchor: .top) }
                }
            }
            }.navigationTitle(focusedPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? toolTitle(group.kind)).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if focusedPath == nil { ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button(String(localized: "Copy All Outputs", bundle: relayLocalizationBundle), systemImage: "doc.on.doc") {
                                UIPasteboard.general.string = liveGroup.items.map { $0.command != nil ? $0.commandOutput : $0.resultSummary ?? $0.text }.joined(separator: "\n\n")
                            }
                        } label: { Image(systemName: "doc.on.doc").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel(String(localized: "Copy Activity", bundle: relayLocalizationBundle))
                    }
                    }
                    ToolbarItem(placement: .confirmationAction) { Button(String(localized: "Close", bundle: relayLocalizationBundle)) { dismiss() } }
                }
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
