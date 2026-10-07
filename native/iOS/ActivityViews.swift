import SwiftUI

struct ToolSummaryView: View {
    let group: TranscriptGroup
    let open: () -> Void
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var running: Int { group.items.filter { $0.state == "running" }.count }
    private var failed: Int { group.items.filter { $0.state == "failed" || $0.state == "declined" }.count }
    private var current: Activity? { group.items.last(where: { $0.state == "running" }) ?? group.items.last }
    private var state: String { running > 0 ? "WORKING" : failed > 0 ? "FAILED" : group.items.allSatisfy { $0.state == "completed" } ? "READY" : "INACTIVE" }
    private var tint: Color { group.kind == .terminal ? RelayPalette.terminal : group.kind == .mcp ? RelayPalette.tool : RelayPalette.file }
    @State private var changeOverview = ""
    private var summary: String {
        var value = group.kind == .changes && !changeOverview.isEmpty ? changeOverview : toolCount(group)
        if running > 0 { value += " · \(running) in corso" }
        if failed > 0 { value += " · \(failed) \(failed == 1 ? "non riuscito" : "non riusciti")" }
        if state == "READY" { value += group.items.count == 1 ? " · completato" : " · completati" }
        return value
    }
    private var preview: String? {
        guard let current else { return nil }
        if let command = current.command { return command }
        if let tool = current.toolName { return [current.toolServer, tool].compactMap { $0 }.joined(separator: " · ") }
        if let files = current.files, !files.isEmpty {
            return files.prefix(3).map { URL(fileURLWithPath: $0.path).lastPathComponent }.joined(separator: ", ")
        }
        return nil
    }
    var body: some View {
        VStack(alignment: .leading, spacing: RelaySpacing.row) {
            Button { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { expanded.toggle() } } label: {
                VStack(alignment: .leading, spacing: RelaySpacing.compact) {
                    HStack(spacing: 10) {
                        Image(systemName: toolIcon(group.kind)).font(.subheadline.weight(.medium)).foregroundStyle(tint)
                            .frame(width: 24, height: 24)
                        Text(toolTitle(group.kind)).font(.subheadline.weight(.semibold))
                        Spacer(minLength: 4)
                        if state != "INACTIVE" { SessionStatusMark(status: state).font(.caption) }
                        Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                    }
                    Text(summary).font(.caption).foregroundStyle(.secondary).padding(.leading, 34)
                        .contentTransition(.opacity)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: state)
                    if let preview {
                        if current?.command != nil { CommandPreviewView(command: preview).lineLimit(expanded || running > 0 ? 2 : 1).padding(.leading, 34) }
                        else { Text(preview).font(.caption).foregroundStyle(.secondary).lineLimit(1).padding(.leading, 34) }
                    }
                }.foregroundStyle(.primary).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(RelayRowPressStyle()).accessibilityIdentifier("tool." + group.id)
                .accessibilityValue(expanded ? "Dettagli aperti" : "Dettagli chiusi")
            if running > 0, group.kind == .terminal, let item = current, !item.commandOutput.isEmpty {
                // A bounded tail is a live preview, not another scrolling terminal.
                Text(item.commandOutput.suffix(600).split(separator: "\n", omittingEmptySubsequences: false).suffix(3).joined(separator: "\n"))
                    .font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 10).overlay(alignment: .leading) { Capsule().fill(tint.opacity(0.4)).frame(width: 2) }
                    .accessibilityIdentifier("tool.live." + group.id)
            }
            if expanded {
                VStack(alignment: .leading, spacing: RelaySpacing.row) {
                    Divider()
                    if group.items.count > 3 { Text("Ultime 3 operazioni").font(.caption2).foregroundStyle(.secondary) }
                    ForEach(Array(group.items.suffix(3))) { item in
                        HStack(alignment: .top, spacing: RelaySpacing.compact) {
                            SessionStatusMark(status: item.state == "running" ? "WORKING" : item.state == "failed" || item.state == "declined" ? "FAILED" : item.state == "completed" ? "READY" : "INACTIVE")
                                .font(.caption).frame(width: 20)
                            VStack(alignment: .leading, spacing: RelaySpacing.small) {
                                if let command = item.command { CommandPreviewView(command: command).lineLimit(3) }
                                else {
                                    Text(item.toolName ?? item.files?.first.map { URL(fileURLWithPath: $0.path).lastPathComponent } ?? toolTitle(group.kind))
                                        .font(.subheadline).lineLimit(3).textSelection(.enabled)
                                }
                                HStack(spacing: 8) {
                                    Text(activityState(item.state))
                                    if let code = item.exitCode { Text("Exit \(code)") }
                                    if let duration = item.durationMs { Text(String(format: "%.1f s", Double(duration) / 1000)) }
                                }.font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button(action: open) {
                        HStack {
                            Text("Apri dettagli e output")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                        }.font(.caption.weight(.semibold)).frame(minHeight: 44)
                    }.accessibilityIdentifier("tool.details." + group.id)
                }.transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }.padding(RelaySpacing.row)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(running > 0 ? tint.opacity(0.25) : Color.primary.opacity(0.04)))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: state)
            .task(id: group.kind == .changes ? group.items.last?.text : nil) {
                guard group.kind == .changes else { return }
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
    private var liveGroup: TranscriptGroup { TranscriptGroup.make(relay.chat.items).first { $0.id == group.id } ?? group }
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: RelaySpacing.page) {
                    HStack {
                        Label(toolCount(liveGroup), systemImage: toolIcon(group.kind))
                        Spacer()
                        let running = liveGroup.items.filter { $0.state == "running" }.count
                        if running > 0 { Text("\(running) in corso").foregroundStyle(RelayPalette.working) }
                    }.font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    ForEach(liveGroup.items) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(item.toolName ?? toolTitle(group.kind)).font(.subheadline.weight(.semibold))
                                Spacer()
                                if item.state == "running" { ProgressView().controlSize(.small) }
                                Text(activityState(item.state)).font(.caption).foregroundStyle(.secondary)
                                Menu {
                                    if let command = item.command { Button("Copia comando", systemImage: "terminal") { UIPasteboard.general.string = command } }
                                    Button("Copia output completo", systemImage: "doc.on.doc") { UIPasteboard.general.string = item.command != nil ? item.commandOutput : item.text }
                                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                                    .accessibilityLabel("Azioni output")
                            }
                            if let server = item.toolServer { Text(server).font(.caption).foregroundStyle(.secondary) }
                            if let command = item.command {
                                ScrollView(.horizontal) { CommandPreviewView(command: command).fixedSize(horizontal: true, vertical: false) }
                                    .contextMenu { Button("Copia comando", systemImage: "doc.on.doc") { UIPasteboard.general.string = command } }
                            }
                            HStack {
                                if let code = item.exitCode { Text("Exit \(code)") }
                                if let milliseconds = item.durationMs { Text(String(format: "%.1f s", Double(milliseconds) / 1000)) }
                                if item.truncated == true { Text("Contenuto parziale") }
                            }.font(.caption).foregroundStyle(.secondary)
                            if item.kind == "diff" {
                                PatchView(patch: item.text)
                            } else if let files = item.files, !files.isEmpty {
                                ForEach(Array(files.enumerated()), id: \.offset) { _, file in
                                    Text(URL(fileURLWithPath: file.path).lastPathComponent + " · " + fileChangeLabel(file.kind)).font(.subheadline)
                                    if let patch = file.patch {
                                        if patch.hasPrefix("diff --git ") || patch.hasPrefix("@@ ") || patch.contains("\n@@ ") {
                                            PatchView(patch: patch, path: file.path)
                                        } else {
                                            CodeBlockView(code: patch, language: URL(fileURLWithPath: file.path).pathExtension)
                                        }
                                    }
                                }
                            } else if group.kind == .terminal {
                                if #available(iOS 18.0, *) {
                                    TerminalOutputView(text: item.command != nil ? item.commandOutput : item.text)
                                        .accessibilityIdentifier("activity." + item.kind + "." + item.id)
                                } else {
                                    CodeBlockView(code: item.command != nil ? item.commandOutput : item.text, language: "output")
                                }
                            } else {
                            ScrollView(.horizontal) {
                                Text(item.command != nil ? item.commandOutput : item.text).font(.callout.monospaced()).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .accessibilityIdentifier("activity." + item.kind + "." + item.id)
                            }.contextMenu { Button("Copia output", systemImage: "doc.on.doc") { UIPasteboard.general.string = item.command != nil ? item.commandOutput : item.text } }
                            }
                        }
                    }
                }.padding(20)
            }.navigationTitle(toolTitle(group.kind)).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button("Copia tutti gli output", systemImage: "doc.on.doc") {
                                UIPasteboard.general.string = liveGroup.items.map { $0.command != nil ? $0.commandOutput : $0.text }.joined(separator: "\n\n")
                            }
                        } label: { Image(systemName: "doc.on.doc").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Copia attività")
                    }
                    ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } }
                }
        }
    }
}

private func toolTitle(_ kind: TranscriptGroup.Kind) -> String {
    switch kind { case .terminal: "Terminale"; case .mcp: "MCP"; case .changes: "Modifiche"; default: "Attività" }
}
private func toolIcon(_ kind: TranscriptGroup.Kind) -> String {
    switch kind { case .terminal: "terminal"; case .mcp: "wrench.and.screwdriver"; case .changes: "doc.text"; default: "list.bullet" }
}
private func toolCount(_ group: TranscriptGroup) -> String {
    let count = group.items.count
    switch group.kind {
    case .terminal: return "\(count) \(count == 1 ? "comando" : "comandi")"
    case .mcp: return "\(count) \(count == 1 ? "operazione" : "operazioni")"
    case .changes: return "\(count) \(count == 1 ? "evento" : "eventi")"
    default: return "\(count) \(count == 1 ? "elemento" : "elementi")"
    }
}

private func activityState(_ state: String?) -> String {
    switch state { case "running": "In corso"; case "completed": "Completato"; case "failed": "Fallito"; case "declined": "Rifiutato"; default: "" }
}

private func fileChangeLabel(_ kind: String) -> String {
    switch kind { case "add", "create": "Creato"; case "delete": "Eliminato"; case "rename", "move": "Rinominato"; default: "Modificato" }
}
