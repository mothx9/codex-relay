import SwiftUI

enum RelaySpacing {
    static let small: CGFloat = 4
    static let compact: CGFloat = 6
    static let row: CGFloat = 12
    static let page: CGFloat = 16
}

struct RootView: View {
    @Environment(RelayController.self) private var relay
    @State private var destination = 0
    @State private var library = false
    @State private var fleetSearch = ""
    @State private var fleetFilter = "ALL"
    @State private var fleetMachine = ""
    var body: some View {
        Group {
            if relay.credential == nil { NavigationStack { PairingView().navigationTitle("Codex Relay").navigationBarTitleDisplayMode(.inline) } }
            else {
                NavigationStack {
                    TabView(selection: $destination) {
                        FleetView(filter: $fleetFilter, machine: $fleetMachine, search: $fleetSearch).tabItem { Label("Fleet", systemImage: "square.grid.2x2") }.tag(0)
                        NeedsYouView().tabItem { Label(String(localized: "Needs You", bundle: relayLocalizationBundle), systemImage: "bubble.left.and.exclamationmark.bubble.right") }
                            .badge(relay.attentionCount).tag(1)
                    }
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button { library = true } label: { Image(systemName: "sidebar.left").frame(minWidth: 44, minHeight: 44) }
                                .accessibilityLabel(String(localized: "Relay menu", bundle: relayLocalizationBundle)).accessibilityIdentifier("navigation.relay")
                        }
                        ToolbarItem(placement: .principal) { Text(destination == 0 ? "Codex Relay" : destination == 1 ? String(localized: "Needs You", bundle: relayLocalizationBundle) : String(localized: "Settings", bundle: relayLocalizationBundle)).font(.headline) }
                        if destination == 0 {
                            ToolbarItem(placement: .topBarTrailing) {
                                Menu {
                                    Picker(String(localized: "Show", bundle: relayLocalizationBundle), selection: $fleetFilter) {
                                        Text(String(localized: "Overview", bundle: relayLocalizationBundle)).tag("ALL")
                                        Text(String(localized: "All sessions", bundle: relayLocalizationBundle)).tag("HISTORY")
                                        ForEach(["NEEDS_YOU", "WORKING", "READY", "FAILED", "OFFLINE"], id: \.self) { Text(statusLabel($0)).tag($0) }
                                    }
                                    Picker(String(localized: "Machine", bundle: relayLocalizationBundle), selection: $fleetMachine) {
                                        Text(String(localized: "All machines", bundle: relayLocalizationBundle)).tag("")
                                        ForEach(relay.machines.values.sorted { $0.name < $1.name }) { Text($0.name).tag($0.id) }
                                    }
                                } label: { Image(systemName: "line.3.horizontal.decrease").frame(minWidth: 44, minHeight: 44) }
                                    .accessibilityLabel(String(localized: "Filter sessions", bundle: relayLocalizationBundle))
                            }
                        }
                    }
                    .navigationTitle(destination == 0 ? "Codex Relay" : destination == 1 ? String(localized: "Needs You", bundle: relayLocalizationBundle) : String(localized: "Settings", bundle: relayLocalizationBundle))
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationDestination(isPresented: Binding(get: { !relay.selected.isEmpty }, set: { if !$0 { relay.closeDetail() } })) {
                        SessionView()
                    }
                }
            }
        }
        .sheet(isPresented: $library) {
            NavigationStack {
                RelayLibraryView {
                    library = false; destination = 0; fleetFilter = "HISTORY"; fleetSearch = ""; fleetMachine = ""
                }.toolbar { ToolbarItem(placement: .confirmationAction) { Button(String(localized: "Close", bundle: relayLocalizationBundle)) { library = false } } }
            }
        }
        .onChange(of: relay.returnToFleet) { _, _ in destination = 0 }
        .safeAreaInset(edge: .top) {
            if let message = relay.navigationStatus {
                HStack {
                    Text(message).font(.caption)
                    Spacer()
                    Button(String(localized: "Dismiss", bundle: relayLocalizationBundle), systemImage: "xmark") { relay.navigationStatus = nil; relay.pendingNavigation = PendingNavigation() }.labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                }.padding(.horizontal, RelaySpacing.page).background(.regularMaterial)
            }
        }
        .sheet(isPresented: Binding(get: { relay.routedMachine != nil && relay.credential != nil }, set: { if !$0 { relay.routedMachine = nil } })) {
            NavigationStack {
                MachineSettingsView(id: relay.routedMachine ?? "")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button(String(localized: "Close", bundle: relayLocalizationBundle)) { relay.routedMachine = nil } } }
            }
        }
        .alert("Codex Relay", isPresented: Binding(get: { relay.error != nil }, set: { if !$0 { relay.error = nil } })) { Button("OK") { relay.error = nil } } message: { Text(relay.error ?? "") }
    }

}
struct PairingView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(RelayController.self) private var relay
    @State private var url = ""
    @State private var code = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: RelaySpacing.row) {
                    Image("RelayMark").resizable().scaledToFit().frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 12)).accessibilityHidden(true)
                    Text(String(localized: "Your Codex fleet.\nOn iPhone.", bundle: relayLocalizationBundle)).font(.title.weight(.semibold))
                    Text(String(localized: "Follow live work, answer questions and continue sessions across your machines.", bundle: relayLocalizationBundle)).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: RelaySpacing.page) {
                    onboardingStep(title: String(localized: "One Hub", bundle: relayLocalizationBundle), detail: String(localized: "Your self-hosted Hub coordinates the fleet.", bundle: relayLocalizationBundle), icon: "network")
                    onboardingStep(title: String(localized: "Agents on your machines", bundle: relayLocalizationBundle), detail: String(localized: "Each Agent connects to the Codex you already use.", bundle: relayLocalizationBundle), icon: "desktopcomputer")
                    onboardingStep(title: String(localized: "This iPhone", bundle: relayLocalizationBundle), detail: String(localized: "Pair once to supervise work and respond securely.", bundle: relayLocalizationBundle), icon: "iphone")
                }
                VStack(alignment: .leading, spacing: RelaySpacing.row) {
                    Text(String(localized: "Pair with your Hub", bundle: relayLocalizationBundle)).font(.headline)
                    TextField("https://your-hub", text: $url)
                        .textContentType(.URL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .padding(RelaySpacing.row).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel(String(localized: "Hub URL", bundle: relayLocalizationBundle)).accessibilityIdentifier("pairing.url")
                    TextField(String(localized: "8-digit pairing code", bundle: relayLocalizationBundle), text: $code)
                        .textContentType(.oneTimeCode).keyboardType(.numberPad).font(.body.monospacedDigit())
                        .padding(RelaySpacing.row).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("pairing.code")
                        .onChange(of: code) { _, value in code = String(value.filter(\.isNumber).prefix(8)) }
                    Text(String(localized: "Create a one-time code on the Hub host or from an authorized controller. It expires after 5 minutes.", bundle: relayLocalizationBundle)).font(.footnote).foregroundStyle(.secondary)
                    if let error = relay.pairingError { Text(error).font(.footnote).foregroundStyle(RelayPalette.attention).accessibilityIdentifier("pairing.error") }
                }
                DisclosureGroup(String(localized: "Need to set up a Hub?", bundle: relayLocalizationBundle)) {
                    VStack(alignment: .leading, spacing: RelaySpacing.row) {
                        Text(String(localized: "Install Relay on an always-on host with an HTTPS address, then create your iPhone pairing code. After pairing, add machines from Relay → Machines.", bundle: relayLocalizationBundle)).font(.footnote)
                        Link(String(localized: "Installation guide", bundle: relayLocalizationBundle), destination: URL(string: "https://github.com/mothx9/codex-relay#quick-start")!)
                    }.padding(.vertical, RelaySpacing.small)
                }
                Text(String(localized: "Access is stored in this iPhone’s Keychain. Your Codex login stays on your machines. Never enter a Hub admin token here.", bundle: relayLocalizationBundle)).font(.footnote).foregroundStyle(.secondary)
            }.padding(RelaySpacing.page)
        }.defaultScrollAnchor(.top).scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task { await relay.pair(url: url, code: code); if relay.credential != nil { code = "" } }
                } label: {
                    HStack {
                        if relay.busy { ProgressView() }
                        Text(relay.busy ? String(localized: "Pairing…", bundle: relayLocalizationBundle) : (dynamicTypeSize.isAccessibilitySize ? String(localized: "Pair", bundle: relayLocalizationBundle) : String(localized: "Pair this iPhone", bundle: relayLocalizationBundle))).font(.body.weight(.semibold)).foregroundStyle(.primary)
                    }.frame(maxWidth: .infinity, minHeight: 48)
                }.buttonStyle(.borderedProminent)
                    .disabled(relay.busy || code.count != 8 || url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("pairing.submit")
                    .padding(RelaySpacing.page).background(.bar)
            }
    }
    private func onboardingStep(title: String, detail: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: RelaySpacing.row) {
            Image(systemName: icon).frame(width: 28, height: 28).foregroundStyle(.secondary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: RelaySpacing.small) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }.accessibilityElement(children: .combine)
    }
}
/// Animate semantic state changes only; deltas keep their existing view identity.
struct SessionStatusMark: View {
    let status: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var symbol: String {
        switch status {
        case "WORKING": "circle.dotted"
        case "NEEDS_YOU": "exclamationmark.bubble.fill"
        case "FAILED": "exclamationmark.circle.fill"
        case "OFFLINE": "network.slash"
        case "SYNCING", "RECONNECTING": "arrow.triangle.2.circlepath"
        case "DEGRADED": "exclamationmark.triangle"
        case "INACTIVE": "moon"
        default: "checkmark.circle"
        }
    }
    var body: some View {
        Group {
            if status == "WORKING" && !reduceMotion {
                ProgressView().controlSize(.mini).tint(statusColor(status))
            } else {
                Image(systemName: symbol).foregroundStyle(statusColor(status))
                    .contentTransition(.symbolEffect(.replace))
            }
        }.frame(width: 16, height: 16)
            .transaction { if reduceMotion { $0.animation = nil; $0.disablesAnimations = true } }
            .accessibilityLabel(status == "OFFLINE" ? String(localized: "Last-known state", bundle: relayLocalizationBundle) : statusLabel(status))
    }
}

struct RelayRowPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.65 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct ElapsedLabel: View {
    let start: String?
    private var date: Date? {
        guard let start else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: start) ?? ISO8601DateFormatter().date(from: start)
    }
    var body: some View {
        if let date, date.timeIntervalSince1970 > 0 {
            Text(date, style: .timer).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing).fixedSize().accessibilityLabel(String(localized: "Turn duration", bundle: relayLocalizationBundle)).accessibilityValue(Text(date, style: .timer))
        }
    }
}

struct NeedsYouView: View {
    @Environment(RelayController.self) private var relay
    private var requests: [PendingRequest] { relay.requests.values.sorted { $0.id < $1.id } }
    var body: some View {
        List {
            if requests.isEmpty && relay.liveQuestions.records.isEmpty {
                ContentUnavailableView(String(localized: "No pending requests", bundle: relayLocalizationBundle), systemImage: "checkmark.bubble", description: Text(String(localized: "Decisions and approvals from your machines will appear here.", bundle: relayLocalizationBundle)))
                    .listRowBackground(Color.clear)
            }
            if !requests.isEmpty {
                Section(String(localized: "Action required", bundle: relayLocalizationBundle)) {
                ForEach(requests) { request in
                    Button { relay.open(request.sessionId) } label: {
                        VStack(alignment: .leading, spacing: RelaySpacing.compact) {
                            Text(relay.machines[request.machineId]?.name ?? request.machineId).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(relay.sessions[request.sessionId]?.title ?? String(localized: "Codex session", bundle: relayLocalizationBundle)).font(.body.weight(.semibold))
                            Label(request.kind == "user_input" ? String(localized: "Codex has a question", bundle: relayLocalizationBundle) : String(localized: "Approval requested", bundle: relayLocalizationBundle), systemImage: "exclamationmark.bubble")
                                .font(.subheadline).foregroundStyle(.orange)
                            if !relay.online || relay.machines[request.machineId]?.status != "ONLINE" { Text(relay.machineConnectionLabel(request.machineId)).font(.caption).foregroundStyle(.secondary) }
                        }.padding(.vertical, RelaySpacing.compact)
                    }.buttonStyle(.plain).accessibilityIdentifier("request." + request.id)
                }
                }
            }
            if !relay.liveQuestions.records.isEmpty {
                Section {
                    ForEach(relay.liveQuestions.records) { question in
                        Button { relay.open(question.sessionID) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(relay.sessions[question.sessionID]?.title ?? String(localized: "Codex session", bundle: relayLocalizationBundle)).font(.subheadline.weight(.semibold))
                                Text(question.activity.questions?.first?.title ?? "").font(.subheadline).lineLimit(3)
                                HStack {
                                    Label(String(localized: "Live question", bundle: relayLocalizationBundle), systemImage: "bubble.left")
                                    Spacer()
                                    Text(question.observedAt, style: .relative)
                                }.font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 4)
                        }.buttonStyle(.plain).accessibilityIdentifier("live-question." + question.activity.id)
                    }
                } header: { Text(String(localized: "Live questions", bundle: relayLocalizationBundle)) }
                footer: { Text(String(localized: "Observed during the current connection. These hints clear when work moves on or the connection is lost.", bundle: relayLocalizationBundle)) }
            }
        }.listStyle(.insetGrouped)
    }
}
struct PendingView: View {
    @Environment(RelayController.self) private var relay
    let request: PendingRequest
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var answers: [String: String] = [:]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(request.kind == "user_input" ? String(localized: "Question", bundle: relayLocalizationBundle) : request.kind == "command_approval" ? String(localized: "Codex wants to run", bundle: relayLocalizationBundle) : request.kind == "file_approval" ? String(localized: "Codex wants to change files", bundle: relayLocalizationBundle) : request.kind == "permissions_approval" ? String(localized: "Codex requests permission", bundle: relayLocalizationBundle) : String(localized: "Codex needs a decision", bundle: relayLocalizationBundle)).font(.headline)
            if !(request.questions ?? []).contains(where: { $0.question.trimmingCharacters(in: .whitespacesAndNewlines) == request.description.trimmingCharacters(in: .whitespacesAndNewlines) }) {
                Text(request.description).textSelection(.enabled)
            }
            if let operation = request.operation { Text(operation).font(.body.monospaced()).textSelection(.enabled) }
            ForEach(request.questions ?? []) { question in
                VStack(alignment: .leading, spacing: RelaySpacing.row) {
                    Text(question.question).textSelection(.enabled)
                    if let options = question.options {
                        ForEach(options, id: \.label) { option in
                            let selected = answers[question.id] == option.label
                            Button {
                                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { answers[question.id] = option.label }
                            } label: {
                                HStack(alignment: .top, spacing: RelaySpacing.row) {
                                    VStack(alignment: .leading, spacing: RelaySpacing.small) {
                                        Text(option.label).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                        Text(option.description).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 4)
                                    Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? Color.accentColor : .secondary)
                                }.padding(RelaySpacing.row).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .background(selected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                            }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                    let binding = Binding(get: { answers[question.id] ?? "" }, set: { answers[question.id] = $0 })
                    Group {
                        if question.secret == true { SecureField(String(localized: "Answer", bundle: relayLocalizationBundle), text: binding) }
                        else { TextField(String(localized: "Custom answer", bundle: relayLocalizationBundle), text: binding, axis: .vertical).lineLimit(1...4) }
                    }.padding(RelaySpacing.row).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            if request.kind == "permissions_approval" {
                Text(String(localized: "Requested permissions · this turn only", bundle: relayLocalizationBundle)).font(.subheadline.bold())
                if let permissions = request.payload?.permissions {
                    Text(permissions.pretty).font(.caption.monospaced()).textSelection(.enabled)
                    if request.canApprove {
                        Button(String(localized: "Grant permissions for this turn", bundle: relayLocalizationBundle)) { Task { await relay.answer(request, decision: "approve") } }.buttonStyle(.bordered)
                            .disabled(!relay.online || relay.machines[request.machineId]?.status != "ONLINE" || relay.current?.capabilities.canAnswer != true)
                    }
                } else { Text(String(localized: "Permission context unavailable: resolve in local Codex.", bundle: relayLocalizationBundle)).font(.caption) }
            }
            if request.kind == "mcp_elicitation" { MCPRequestForm(request: request) }
            if request.canApprove && ["user_input", "command_approval", "file_approval"].contains(request.kind) {
                Button(request.kind == "user_input" ? String(localized: "Respond", bundle: relayLocalizationBundle) : String(localized: "Approve Once", bundle: relayLocalizationBundle)) { Task { await relay.answer(request, decision: "approve", answers: answers.mapValues { [$0] }) } }.buttonStyle(.bordered).disabled(!relay.online || relay.machines[request.machineId]?.status != "ONLINE" || relay.current?.capabilities.canAnswer != true || (request.kind == "user_input" && (request.questions ?? []).contains { (answers[$0.id] ?? "").isEmpty }))
            }
            if request.kind != "unsupported" { Button(String(localized: "Reject", bundle: relayLocalizationBundle), role: .destructive) { Task { await relay.answer(request, decision: "reject") } }.disabled(!relay.online || relay.machines[request.machineId]?.status != "ONLINE" || relay.current?.capabilities.canAnswer != true) }
            if let progress = relay.requestProgress[request.presentationID] {
                Text(progress).font(.caption).foregroundStyle(.secondary)
            }
            if let error = relay.requestErrors[request.presentationID] {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
        }.padding(RelaySpacing.row).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(RelayPalette.attention.opacity(0.3)))
            .disabled(relay.requestProgress[request.presentationID] != nil)
    }
}
struct MCPRequestForm: View {
    @Environment(RelayController.self) private var relay
    let request: PendingRequest
    @State private var fields: [String: String] = [:]
    @State private var raw = "{}"
    @State private var editJSON = false
    private var schema: JSONValue? { request.payload?.inputSchema }
    private var properties: [String: JSONValue] { schema?.object?["properties"]?.object ?? [:] }
    private var simple: Bool {
        schema?.object?["type"]?.string == "object" && !properties.isEmpty && properties.values.allSatisfy {
            $0.object?["enum"]?.array != nil || ["string", "number", "integer", "boolean"].contains($0.object?["type"]?.string ?? "")
        }
    }
    private var response: JSONValue? {
        guard let schema else { return nil }
        return try? editJSON || !simple ? MCPResponse.parse(raw, schema: schema) : MCPResponse.fields(fields, schema: schema)
    }
    private var validation: String? {
        guard let schema else { return String(localized: "Schema unavailable: resolve in local Codex.", bundle: relayLocalizationBundle) }
        do { _ = try editJSON || !simple ? MCPResponse.parse(raw, schema: schema) : MCPResponse.fields(fields, schema: schema); return nil }
        catch { return error.localizedDescription }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let schema {
                DisclosureGroup(String(localized: "Full MCP schema", bundle: relayLocalizationBundle)) { Text(schema.pretty).font(.caption.monospaced()).textSelection(.enabled) }
                if request.canApprove {
                    if simple && !editJSON {
                        ForEach(properties.keys.sorted(), id: \.self) { key in
                            let property = properties[key]!.object ?? [:]
                            let binding = Binding(get: { fields[key] ?? "" }, set: { fields[key] = $0 })
                            let required = schema.object?["required"]?.array?.contains(.string(key)) == true
                            VStack(alignment: .leading, spacing: 4) {
                                Text((property["title"]?.string ?? key) + (required ? " *" : "")).font(.subheadline.bold())
                                if let description = property["description"]?.string { Text(description).font(.caption).foregroundStyle(.secondary) }
                                if let options = property["enum"]?.array {
                                    Picker(key, selection: binding) {
                                        Text(String(localized: "Choose…", bundle: relayLocalizationBundle)).tag("")
                                        ForEach(options.map { $0.string ?? $0.pretty }, id: \.self) { Text($0).tag($0) }
                                    }.pickerStyle(.menu)
                                } else if property["type"]?.string == "boolean" {
                                    Picker(key, selection: binding) { Text(String(localized: "Choose…", bundle: relayLocalizationBundle)).tag(""); Text(String(localized: "Yes", bundle: relayLocalizationBundle)).tag("true"); Text("No").tag("false") }.pickerStyle(.segmented)
                                } else if property["writeOnly"] == .bool(true) || property["format"] == .string("password") {
                                    SecureField(key, text: binding)
                                } else { TextField(key, text: binding).textInputAutocapitalization(.never).autocorrectionDisabled() }
                            }
                        }
                        Button(String(localized: "Edit response as JSON", bundle: relayLocalizationBundle)) { raw = (try? MCPResponse.fields(fields, schema: schema))?.pretty ?? "{}"; editJSON = true }
                    } else {
                        Text(String(localized: "JSON response matching the schema", bundle: relayLocalizationBundle)).font(.caption)
                        TextEditor(text: $raw).font(.body.monospaced()).frame(minHeight: 120).accessibilityLabel(String(localized: "MCP JSON response", bundle: relayLocalizationBundle))
                    }
                    if let validation { Text(validation).font(.caption).foregroundStyle(.orange) }
                    Button(String(localized: "Send MCP response", bundle: relayLocalizationBundle)) { if let response { Task { await relay.answer(request, decision: "approve", content: response) } } }.buttonStyle(.bordered)
                        .disabled(response == nil || !relay.online || relay.machines[request.machineId]?.status != "ONLINE" || relay.current?.capabilities.canAnswer != true)
                } else { Text(String(localized: "This MCP flow requires local Codex.", bundle: relayLocalizationBundle)).font(.caption) }
            } else { Text(String(localized: "Schema unavailable: resolve in local Codex.", bundle: relayLocalizationBundle)).font(.caption) }
        }
    }
}
func statusLabel(_ status: String) -> String { ["SYNCING": String(localized: "Syncing with Codex…", bundle: relayLocalizationBundle), "RECONNECTING": String(localized: "Reconnecting…", bundle: relayLocalizationBundle), "DEGRADED": String(localized: "Codex not connected", bundle: relayLocalizationBundle), "OFFLINE": String(localized: "Relay not connected", bundle: relayLocalizationBundle), "ALL": String(localized: "All", bundle: relayLocalizationBundle), "NEEDS_YOU": String(localized: "Needs You", bundle: relayLocalizationBundle), "WORKING": String(localized: "Working", bundle: relayLocalizationBundle), "READY": String(localized: "Ready", bundle: relayLocalizationBundle), "INACTIVE": String(localized: "Inactive", bundle: relayLocalizationBundle), "FAILED": String(localized: "Error", bundle: relayLocalizationBundle)][status] ?? status }
func statusColor(_ status: String) -> Color { RelayPalette.status(status) }

#if DEBUG
// Explicitly sandboxed fixtures: no Keychain access, Hub transport or notification consent.
@MainActor enum PreviewData {
    static func decode<T: Decodable>(_ text: String, as: T.Type = T.self) -> T {
        try! RelayJSON.decoder().decode(T.self, from: Data(text.utf8))
    }
    static func conversation(long: Bool = false) -> RelayController {
        let relay = controller()
        let session: RelaySession = decode(#"{"id":"laptop~conversation-preview","machine_id":"laptop","thread_id":"conversation-preview","title":"Clona e avvia…","project":"Developer","cwd":"/demo/Developer","branch":"main","status":"WORKING","updated_at":"2026-10-06T12:00:00Z","turn_id":"preview-turn","read_only":false,"capabilities":{"can_send":true,"can_follow_up":true,"can_steer":true,"can_interrupt":true,"can_answer":true}}"#)
        relay.sessions[session.id] = session; relay.selected = session.id
        relay.chat = RecentChat(); relay.outbox = Outbox()
        relay.chat.put(Activity(id: "preview-summary", kind: "agentMessage", text: "Ho aggiornato la struttura del sito e sto verificando gli asset.\n\n### Verifica\n- logo sostituito\n- responsive controllato\n- server locale attivo"))
        for index in 0..<3 { relay.chat.put(Activity(id: "preview-command-\(index)", kind: "commandExecution", text: ["pwd\n/demo/Developer", "git status --short\nWorking tree clean", "npm run build\nBuild completata"][index])) }
        for index in 0..<6 { relay.chat.put(Activity(id: "preview-mcp-\(index)", kind: "mcpToolCall", text: "Operazione dimostrativa \(index + 1) · dati fittizi")) }
        if long {
            for index in 0..<15 {
                relay.chat.put(Activity(id: "preview-history-\(index)", kind: "agentMessage", text: "Controllo \(index + 1)\n\nQuesta conversazione di esempio verifica che il composer rimanga accessibile mentre scorri i messaggi precedenti. I dati sono fittizi e non vengono inviati al Hub."))
            }
        }
        relay.chat.put(Activity(id: "preview-question", kind: "agentMessage", text: "Come procediamo?", questions: [AsyncQuestion(title: "Come procediamo?", options: ["Solo verifica", "Applica la modifica"])]))
        let id = try! relay.outbox.add(id: "preview-queued", session: session.id, kind: "follow_up", text: "Controlla anche la pagina donazioni, ma non cambiare ancora il testo.")
        relay.outbox.sending(id); relay.outbox.result(decode(#"{"id":"preview-queued","ok":true}"#))
        return relay
    }
    static func controller(status: String = "WORKING", paired: Bool = true) -> RelayController {
        let relay = RelayController(preview: true)
        guard paired else { return relay }
        relay.credential = decode(#"{"id":"preview-device","token":"fictional-preview-only","kind":"operator","expires_at":"2027-01-01T00:00:00Z","hub_url":"https://preview.invalid"}"#)
        let machines: [Machine] = decode(#"[{"id":"workstation","name":"WORKSTATION","status":"ONLINE","last_seen":"2026-10-06T12:00:00Z","codex_version":"0.160.1","account":{"kind":"chatgpt","email":"demo@example.invalid","plan":"plus"}},{"id":"laptop","name":"LAPTOP","status":"ONLINE","last_seen":"2026-10-06T12:00:00Z"},{"id":"node","name":"NODE","status":"OFFLINE","last_seen":"2026-10-06T11:00:00Z"}]"#)
        relay.machines = Dictionary(uniqueKeysWithValues: machines.map { ($0.id, $0) })
        var session: RelaySession = decode(#"{"id":"workstation~preview","machine_id":"workstation","thread_id":"preview","title":"Verifica controlli nativi","project":"Demo","cwd":"/demo","branch":"main","status":"WORKING","updated_at":"2026-10-06T12:00:00Z","turn_id":"preview-turn","read_only":false,"capabilities":{"can_send":true,"can_follow_up":true,"can_steer":true,"can_interrupt":true,"can_answer":true}}"#)
        session.status = status; relay.sessions = [session.id: session]; relay.selected = session.id
        relay.online = true; relay.connection = "Preview · dati fittizi"
        relay.chat.put(Activity(id: "demo-user", kind: "userMessage", text: "Verifica lo stato della sessione."))
        relay.chat.put(Activity(id: "demo-agent", kind: "agentMessage", text: "La verifica è in corso. Puoi aggiungere un follow-up."))
        if status == "WORKING" {
            let id = try! relay.outbox.add(id: "preview-follow-up", session: session.id, kind: "follow_up", text: "Al termine riporta i controlli eseguiti.")
            relay.outbox.sending(id)
            relay.outbox.result(decode(#"{"id":"preview-follow-up","ok":true}"#))
        }
        if status == "NEEDS_YOU" {
            let request: PendingRequest = decode(#"{"request_id":"preview-question","session_id":"workstation~preview","machine_id":"workstation","kind":"user_input","description":"Seleziona la verifica da eseguire.","cwd":"/demo","expires_at":"2027-01-01T00:00:00Z","can_approve":true,"questions":[{"id":"scope","header":"Verifica","question":"Quale controllo eseguo?","options":[{"label":"Completo","description":"Esegue tutti i controlli della demo."},{"label":"Rapido","description":"Controlla soltanto lo stato."}]}]}"#)
            relay.requests = [request.id: request]
        }
        relay.registry = decode(#"{"operators":[{"id":"preview-device","name":"iPhone demo","created_at":"2026-10-06T00:00:00Z","expires_at":"2027-01-01T00:00:00Z","last_seen":"2026-10-06T12:00:00Z","revoked":false}],"machines":[],"current_device_id":"preview-device","hub_url":"https://preview.invalid","chatgpt_device_management":false}"#)
        relay.registry = DeviceRegistry(operators: relay.registry!.operators, machines: machines.map { MachineDevice(machine: $0, access: $0.status == "OFFLINE" ? "PAUSED" : "ALLOWED") }, currentDeviceId: "preview-device", hubUrl: "https://preview.invalid", chatgptDeviceManagement: false)
        return relay
    }
}
@MainActor private struct RelayPreview<Content: View>: View {
    @State private var relay: RelayController
    private let content: Content
    init(status: String = "WORKING", paired: Bool = true, @ViewBuilder content: () -> Content) {
        _relay = State(initialValue: PreviewData.controller(status: status, paired: paired))
        self.content = content()
    }
    var body: some View { NavigationStack { content }.environment(relay).preferredColorScheme(.dark) }
}
#Preview("Abbinamento · isolato") { RelayPreview(paired: false) { PairingView() } }
#Preview("Fleet · isolata") { RelayPreview { FleetView(filter: .constant("ALL"), machine: .constant(""), search: .constant("")) } }
#Preview("Sessione · Ready") { RelayPreview(status: "READY") { SessionView() } }
#Preview("Sessione · Follow-up in coda") { RelayPreview { SessionView() } }
#Preview("Sessione · Needs You") { RelayPreview(status: "NEEDS_YOU") { SessionView() } }
#Preview("Dispositivi · isolati") { RelayPreview { DevicesView() } }
@MainActor private struct ConversationPreview: View {
    @State private var relay = PreviewData.conversation()
    var body: some View { NavigationStack { SessionView() }.environment(relay).preferredColorScheme(.dark) }
}
#Preview("Chat · riferimento iPhone") { ConversationPreview() }
#endif

struct LastKnownSession: View {
    let session: RelaySession
    let machine: Machine?
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(localized: "Last known: \(statusLabel(session.status))", bundle: relayLocalizationBundle))
            if let value = machine?.lastSeen, let date = ISO8601DateFormatter().date(from: value) ?? Self.fractional.date(from: value) {
                HStack(spacing: 4) { Text(String(localized: "Last seen", bundle: relayLocalizationBundle)); Text(date, style: .relative) }
            }
        }.font(.caption).foregroundStyle(.secondary)
    }
    private static var fractional: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return formatter
    }
}

#if DEBUG
/// Public assets exercise production views with a closed, in-memory controller.
/// These identities are fictional and this mode never reads Keychain or opens a socket.
@MainActor enum ProductFixtures {
    static let patch = """
    diff --git a/src/validation.rs b/src/validation.rs
    --- a/src/validation.rs
    +++ b/src/validation.rs
    @@ -14,4 +14,7 @@
     pub fn validate(input: &Input) -> Result<()> {
    -    run_checks(input)
    +    if input.is_empty() {
    +        return Err(Error::EmptyInput);
    +    }
    +    run_checks(input)?;
    +    Ok(())
     }
    """
    static func controller(surface: String) -> RelayController {
        let relay = PreviewData.controller()
        let now = Date()
        let stamp = ISO8601DateFormatter().string(from: now)
        func decode<T: Decodable>(_ value: Any, as: T.Type = T.self) -> T {
            try! RelayJSON.decoder().decode(T.self, from: JSONSerialization.data(withJSONObject: value))
        }
        let specs = [("workstation", "Workstation", "ONLINE"), ("laptop", "Laptop", "ONLINE"), ("node", "GPU node", "OFFLINE")]
        let machines: [Machine] = specs.map { id, name, status in
            decode(["id": id, "name": name, "status": status, "last_seen": stamp, "agent_version": "0.1.0-rc.5", "codex_version": "0.160.1", "adapter": "app-server", "freshness": ["protocol_version": 1, "last_heartbeat": stamp, "last_snapshot": stamp, "last_event": stamp, "snapshot_ms": 84, "sync_ms": 102, "sequence": 42, "snapshot_sequence": 40]])
        }
        relay.machines = Dictionary(uniqueKeysWithValues: machines.map { ($0.id, $0) })
        let sessionSpecs = [("laptop", "decision", "Validate the release", "relay", "NEEDS_YOU"), ("workstation", "build", "Harden input validation", "compiler", "WORKING"), ("laptop", "docs", "Update installation guide", "relay", "READY"), ("node", "kernel", "Check CUDA kernels", "compute", "WORKING")]
        let sessions: [RelaySession] = sessionSpecs.enumerated().map { index, spec in
            let (machine, thread, title, project, status) = spec
            return decode(["id": machine + "~" + thread, "machine_id": machine, "thread_id": thread, "title": title, "project": project, "cwd": "/workspace/" + project, "branch": "main", "status": status, "updated_at": ISO8601DateFormatter().string(from: now.addingTimeInterval(Double(-index * 60))), "turn_id": "example-turn", "turn_started": ISO8601DateFormatter().string(from: now.addingTimeInterval(-267)), "read_only": false, "capabilities": ["can_send": true, "can_follow_up": true, "can_steer": true, "can_interrupt": true, "can_answer": true]])
        }
        relay.sessions = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        relay.liveActivities = ["workstation~build": decode(["item_id": "example-command", "kind": "terminal", "label": "cargo test --workspace", "state": "running", "timestamp": stamp])]
        let request: PendingRequest = decode(["request_id": "example-request", "session_id": "laptop~decision", "machine_id": "laptop", "kind": "user_input", "description": "Which validation scope should I use?", "expires_at": "2099-01-01T00:00:00Z", "created_at": stamp, "can_approve": true, "questions": [["id": "scope", "header": "Validation", "question": "Which validation scope should I use?", "options": [["label": "Full suite", "description": "Run unit tests and integration checks."], ["label": "Focused checks", "description": "Run tests for the changed module."]]]]])
        relay.requests = [request.id: request]
        relay.selected = ["conversation", "terminal", "tools", "diff", "live-question", "history-question", "compaction"].contains(surface) ? "workstation~build" : surface == "question" ? "laptop~decision" : ""
        relay.outbox = Outbox(); relay.chat = RecentChat()
        relay.chat.put(Activity(id: "example-user", kind: "userMessage", text: "Validate empty inputs, then run the workspace tests."))
        relay.chat.put(Activity(id: "example-response", kind: "agentMessage", text: "I added an **empty-input guard** and a regression test. The workspace suite is running."))
        var command = Activity(id: "example-command", kind: "commandExecution", text: "cargo test --workspace\nCompiling validator v0.4.0\nRunning tests/validation.rs\ntest rejects_empty_input ... ok\ntest preserves_valid_input ... ok\nRunning integration checks…")
        command.command = "cargo test --workspace"; command.state = "running"; command.timestamp = stamp
        relay.chat.put(command)
        var tool = Activity(id: "example-tool", kind: "mcpToolCall", text: "fetch_document")
        tool.toolName = "fetch_document"; tool.toolServer = "documentation"; tool.state = surface == "tools" ? "running" : "completed"; tool.progress = "Reading the validation API reference"
        relay.chat.put(tool)
        var file = Activity(id: "example-file", kind: "fileChange", text: "src/validation.rs")
        file.state = "completed"; file.files = decode([["path": "src/validation.rs", "kind": "modify", "patch": patch]])
        relay.chat.put(file)
        if ["terminal", "tools", "diff"].contains(surface) {
            relay.chat = RecentChat(); relay.chat.put(surface == "terminal" ? command : surface == "tools" ? tool : file)
        }
        if surface == "conversation" {
            relay.chat.put(Activity(id: "example-code", kind: "agentMessage", text: "The guard keeps the failure explicit:\n\n```rust\nif input.is_empty() {\n    return Err(Error::EmptyInput);\n}\nrun_checks(input)?;\n```\n\nThe regression test has passed. Integration checks are still running."))
        }
        if surface == "question" { relay.chat = RecentChat(); relay.chat.put(Activity(id: "example-question-intro", kind: "agentMessage", text: "The release candidate is ready for validation. I need your choice before starting the checks.")) }
        if ["live-question", "history-question", "live-inbox"].contains(surface) {
            relay.requests = [:]; relay.chat = RecentChat()
            let event: RelayEvent = decode(["kind": "activity", "session_id": "workstation~build", "turn_id": "example-turn", "activity": ["id": "example-async", "kind": "agentMessage", "text": "Which validation scope should I use?", "questions": [["title": "Which validation scope should I use?", "options": ["Full suite", "Focused checks"]]]]])
            relay.chat.apply(event)
            if surface != "history-question" { relay.liveQuestions.observe(event, activeTurn: "example-turn", current: true) }
        }
        if surface == "compaction" {
            var item = Activity(id: "example-compaction", kind: "context_compaction", text: "Context compacted")
            item.state = "running"; item.turnId = "example-turn"; relay.chat.put(item)
            relay.liveActivities["workstation~build"] = decode(["item_id": item.id, "kind": item.kind, "state": "running", "label": "", "timestamp": stamp])
        }
        let account: AccountEntry = decode(["id": "example-account", "identity_basis": "account_id", "account": ["kind": "chatgpt", "email": "developer@example.invalid", "plan": "Pro", "source": "codex", "observed_at": stamp, "limits": ["primary": ["used_percent": 61, "window_duration_mins": 300, "resets_at": Int(now.timeIntervalSince1970) + 8040], "secondary": ["used_percent": 31, "window_duration_mins": 10080, "resets_at": Int(now.timeIntervalSince1970) + 172800]]], "machines": ["workstation", "laptop"], "source_machine": "laptop", "fresh": true, "updated_at": stamp])
        relay.accounts = [account]
        relay.registry = DeviceRegistry(operators: relay.registry!.operators, machines: machines.map { MachineDevice(machine: $0, access: "ALLOWED") }, currentDeviceId: "preview-device", hubUrl: "https://relay.example.invalid", chatgptDeviceManagement: false)
        relay.diagnostics = decode(["hub_version": "0.1.0-rc.5", "protocol_version": 1, "transport": "HTTPS / WSS", "database": "reachable", "machines": []])
        relay.diagnosticsUpdatedAt = now
        if surface == "notifications" { relay.notificationsEnabled = true; relay.notificationAllowed = true; relay.notificationPermission = "Allowed" }
        relay.connection = "Connected"; relay.online = true
        return relay
    }
}
@MainActor struct ProductPreviewScreen: View {
    let surface: String
    @State private var relay: RelayController
    init(surface: String) { self.surface = surface; _relay = State(initialValue: ProductFixtures.controller(surface: surface)) }
    var body: some View {
        Group {
            switch surface {
            case "fleet": RootView()
            case "conversation", "question", "live-question", "history-question", "compaction": NavigationStack { SessionView() }
            case "needs-you", "live-inbox": NavigationStack { NeedsYouView().navigationTitle("Needs You") }
            case "navigation": NavigationStack { RelayLibraryView(openHistory: {}) }
            case "machine-diagnostics": NavigationStack { MachineDiagnosticsView(id: "workstation") }
            case "machines": NavigationStack { MachinesView() }
            case "account": NavigationStack { AccountDetailView(id: "example-account") }
            case "notifications": NavigationStack { NotificationSettingsView() }
            case "settings": NavigationStack { DevicesView() }
            case "diagnostics": NavigationStack { DiagnosticsView() }
            case "pairing": NavigationStack { PairingView().navigationTitle("Codex Relay").navigationBarTitleDisplayMode(.inline) }
            case "terminal", "tools", "diff":
                let kind: TranscriptGroup.Kind = surface == "terminal" ? .terminal : surface == "tools" ? .mcp : .changes
                if let group = TranscriptGroup.make(relay.chat.items).first(where: { $0.kind == kind }) { ToolDetailView(group: group) }
            default: RootView()
            }
        }.environment(relay).preferredColorScheme(.dark)
            .onChange(of: relay.selected) { _, selected in
                // The public walkthrough exercises production navigation with isolated content.
                guard surface == "fleet", !selected.isEmpty else { return }
                relay.chat = ProductFixtures.controller(surface: selected == "workstation~build" ? "conversation" : "question").chat
            }
    }
}
#Preview("Product · Fleet") { ProductPreviewScreen(surface: "fleet") }
#Preview("Product · Conversation") { ProductPreviewScreen(surface: "conversation") }
#Preview("Product · Terminal") { ProductPreviewScreen(surface: "terminal") }
#Preview("Product · Diff") { ProductPreviewScreen(surface: "diff") }
#Preview("Product · Account") { ProductPreviewScreen(surface: "account") }
#Preview("Product · Needs You") { ProductPreviewScreen(surface: "question") }
#endif
