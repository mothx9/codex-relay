import SwiftUI

enum RelaySpacing {
    static let small: CGFloat = 4
    static let compact: CGFloat = 6
    static let row: CGFloat = 12
    static let page: CGFloat = 16
}

struct RootView: View {
    @EnvironmentObject var relay: RelayController
    @State private var destination = 0
    var body: some View {
        Group {
            if relay.credential == nil { NavigationStack { PairingView().navigationTitle("Codex Relay") } }
            else {
                TabView(selection: $destination) {
                    stack("Codex Relay", tab: 0) { FleetView() }
                        .tabItem { Label("Fleet", systemImage: "square.grid.2x2") }.tag(0)
                    stack("Needs You", tab: 1) { NeedsYouView() }
                        .tabItem { Label("Needs You", systemImage: "bubble.left.and.exclamationmark.bubble.right") }
                        .badge(relay.requests.count).tag(1)
                    stack("Impostazioni", tab: 2) { DevicesView() }
                        .tabItem { Label("Impostazioni", systemImage: "gearshape") }.tag(2)
                }
            }
        }
        .alert("Codex Relay", isPresented: Binding(get: { relay.error != nil }, set: { if !$0 { relay.error = nil } })) { Button("OK") { relay.error = nil } } message: { Text(relay.error ?? "") }
    }
    private func stack<Content: View>(_ title: String, tab: Int, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            content().navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .navigationDestination(isPresented: Binding(get: { destination == tab && !relay.selected.isEmpty }, set: { if !$0 && destination == tab { relay.closeDetail() } })) {
                    SessionView().toolbar(.hidden, for: .tabBar)
                }
        }
    }
}
struct PairingView: View {
    @EnvironmentObject var relay: RelayController
    @State private var url = ""
    @State private var code = ""
    var body: some View {
        Form {
            Section("Collega questo iPhone") {
                Text("Sul computer genera un codice dal Hub, oppure da Dispositivi su un client già abbinato. È valido per 5 minuti.").foregroundStyle(.secondary)
                TextField("https://tuo-hub", text: $url).textContentType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("pairing.url")
                TextField("Codice di 8 cifre", text: $code).textContentType(.oneTimeCode).accessibilityIdentifier("pairing.code")
                Button(relay.busy ? "Abbinamento…" : "Abbina") { Task { await relay.pair(url: url, code: code); code = "" } }.disabled(relay.busy || code.filter(\.isNumber).count != 8).accessibilityIdentifier("pairing.submit")
            }
            Section { Text("L’accesso di questo dispositivo è protetto nel Portachiavi iOS. Il token amministratore rimane sul Hub.").font(.footnote).foregroundStyle(.secondary) }
        }
    }
}
struct FleetView: View {
    @EnvironmentObject var relay: RelayController
    @State private var filter = "ALL"
    @State private var search = ""
    private var browsingAll: Bool { !search.isEmpty || filter != "ALL" }
    private var sorted: [RelaySession] { relay.sessions.values.sorted { $0.updatedAt == $1.updatedAt ? $0.id < $1.id : $0.updatedAt > $1.updatedAt } }
    private func state(_ session: RelaySession) -> String { session.displayStatus(machine: relay.machines[session.machineId], connected: relay.online) }
    private var visible: [RelaySession] { sorted.filter { (filter == "ALL" || filter == "HISTORY" || state($0) == filter) && (search.isEmpty || "\($0.title) \($0.project) \($0.machineId)".localizedCaseInsensitiveContains(search)) } }
    var body: some View {
        List {
            if !browsingAll {
                Section {
                    VStack(alignment: .leading, spacing: RelaySpacing.row) {
                        Text(relay.online ? "\(relay.machines.values.filter { $0.status == "ONLINE" }.count) macchine online" : "Connessione al Hub…")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .accessibilityIdentifier("fleet.connection")
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: RelaySpacing.page) { machineLabels }
                            VStack(alignment: .leading, spacing: RelaySpacing.compact) { machineLabels }
                        }
                    }.padding(.vertical, RelaySpacing.compact)
                }.listRowBackground(Color.clear).listRowSeparator(.hidden)
                sessionSection("Needs You", sessions: sorted.filter { state($0) == "NEEDS_YOU" })
                sessionSection("In corso", sessions: sorted.filter { state($0) == "WORKING" })
                sessionSection("Recenti", sessions: Array(sorted.filter { !["WORKING", "NEEDS_YOU"].contains(state($0)) }.prefix(12)))
                Section {
                    Button { filter = "HISTORY" } label: { Label("Tutte le sessioni · \(relay.sessions.count)", systemImage: "clock.arrow.circlepath") }
                }
            } else {
                Section(filter == "HISTORY" || filter == "ALL" ? "Sessioni" : statusLabel(filter)) {
                    ForEach(visible) { session in FleetSessionRow(session: session) }
                    if visible.isEmpty && filter != "HISTORY" { ContentUnavailableView.search(text: search) }
                }
            }
        }
        .listStyle(.insetGrouped).listSectionSpacing(RelaySpacing.row)
        .searchable(text: $search, prompt: "Sessione, macchina o progetto")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Mostra", selection: $filter) {
                        Text("Panoramica").tag("ALL")
                        Text("Tutte le sessioni").tag("HISTORY")
                        ForEach(["NEEDS_YOU", "WORKING", "READY", "FAILED", "OFFLINE"], id: \.self) { Text(statusLabel($0)).tag($0) }
                    }
                } label: { Image(systemName: filter == "ALL" ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill").frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel("Filtra sessioni")
            }
        }
    }
    private var machineLabels: some View {
        ForEach(relay.machines.values.sorted { $0.name < $1.name }) { machine in
            let online = relay.online && machine.status == "ONLINE"
            Label(machine.name, systemImage: online ? "checkmark.circle.fill" : "network.slash")
                .font(.caption.weight(.medium)).foregroundStyle(online ? Color.primary : Color.secondary)
                .accessibilityLabel("\(machine.name), \(online ? "online" : "offline")").accessibilityIdentifier("fleet.machine." + machine.id)
        }
    }
    @ViewBuilder private func sessionSection(_ title: String, sessions: [RelaySession]) -> some View {
        if !sessions.isEmpty { Section(title) { ForEach(sessions) { FleetSessionRow(session: $0) } } }
    }
}

struct FleetSessionRow: View {
    @EnvironmentObject var relay: RelayController
    let session: RelaySession
    private var status: String { session.displayStatus(machine: relay.machines[session.machineId], connected: relay.online) }
    var body: some View {
        Button { relay.open(session.id) } label: {
            VStack(alignment: .leading, spacing: RelaySpacing.compact) {
                HStack {
                    Text(relay.machines[session.machineId]?.name ?? session.machineId).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Label(statusLabel(status), systemImage: status == "OFFLINE" ? "network.slash" : status == "NEEDS_YOU" ? "exclamationmark.bubble.fill" : status == "WORKING" ? "circle.dotted" : status == "FAILED" ? "exclamationmark.circle" : "checkmark")
                        .font(.caption).foregroundStyle(statusColor(status))
                }
                Text(session.title).font(.body.weight(.semibold)).lineLimit(2).foregroundStyle(.primary)
                HStack {
                    Text(session.project).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    if status == "WORKING" { ElapsedLabel(start: session.turnStarted) }
                }
            }.padding(.vertical, RelaySpacing.small).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).alignmentGuide(.listRowSeparatorLeading) { _ in 0 }.accessibilityIdentifier("session." + session.id)
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
                .multilineTextAlignment(.trailing).fixedSize().accessibilityLabel("Durata del turno").accessibilityValue(Text(date, style: .timer))
        }
    }
}

struct NeedsYouView: View {
    @EnvironmentObject var relay: RelayController
    private var requests: [PendingRequest] { relay.requests.values.sorted { $0.id < $1.id } }
    var body: some View {
        List {
            if requests.isEmpty {
                ContentUnavailableView("Nessuna richiesta", systemImage: "checkmark.bubble", description: Text("Le decisioni e le approvazioni delle tue macchine appariranno qui."))
                    .listRowBackground(Color.clear)
            } else {
                ForEach(requests) { request in
                    Button { relay.open(request.sessionId) } label: {
                        VStack(alignment: .leading, spacing: RelaySpacing.compact) {
                            Text(relay.machines[request.machineId]?.name ?? request.machineId).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(relay.sessions[request.sessionId]?.title ?? "Sessione Codex").font(.body.weight(.semibold))
                            Label(request.kind == "user_input" ? "Codex ha una domanda" : "Approvazione richiesta", systemImage: "exclamationmark.bubble")
                                .font(.subheadline).foregroundStyle(.orange)
                            if !relay.online || relay.machines[request.machineId]?.status != "ONLINE" { Text("Macchina offline").font(.caption).foregroundStyle(.secondary) }
                        }.padding(.vertical, RelaySpacing.compact)
                    }.buttonStyle(.plain).accessibilityIdentifier("request." + request.id)
                }
            }
        }.listStyle(.insetGrouped)
    }
}
struct PendingView: View {
    @EnvironmentObject var relay: RelayController
    let request: PendingRequest
    @State private var answers: [String: String] = [:]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NEEDS YOU · \(request.kind)").font(.headline).foregroundStyle(.orange)
            Text("\(request.machineId) · \(relay.current?.project ?? "") · \(request.cwd ?? relay.current?.cwd ?? "")").font(.caption.monospaced())
            Text(request.description).textSelection(.enabled)
            if let operation = request.operation { Text(operation).font(.body.monospaced()).textSelection(.enabled) }
            ForEach(request.questions ?? []) { question in
                VStack(alignment: .leading) {
                    Text(question.question)
                    if let options = question.options { ForEach(options, id: \.label) { option in Button { answers[question.id] = option.label } label: { VStack(alignment: .leading) { Text((answers[question.id] == option.label ? "✓ " : "") + option.label); Text(option.description).font(.caption).foregroundStyle(.secondary) } } } }
                    let binding = Binding(get: { answers[question.id] ?? "" }, set: { answers[question.id] = $0 })
                    if question.secret == true { SecureField("Risposta", text: binding) } else { TextField("Risposta libera", text: binding) }
                }
            }
            if request.kind == "permissions_approval" {
                Text("Permessi richiesti · soltanto per questo turno").font(.subheadline.bold())
                if let permissions = request.payload?.permissions {
                    Text(permissions.pretty).font(.caption.monospaced()).textSelection(.enabled)
                    if request.canApprove {
                        Button("Concedi i permessi per questo turno") { Task { await relay.answer(request, decision: "approve") } }.buttonStyle(.bordered)
                            .disabled(!relay.online || relay.machines[request.machineId]?.status != "ONLINE" || relay.current?.capabilities.canAnswer != true)
                    }
                } else { Text("Contesto dei permessi non disponibile: risolvi da Codex locale.").font(.caption) }
            }
            if request.kind == "mcp_elicitation" { MCPRequestForm(request: request) }
            if request.canApprove && ["user_input", "command_approval", "file_approval"].contains(request.kind) {
                Button(request.kind == "user_input" ? "Rispondi" : "Approva una volta") { Task { await relay.answer(request, decision: "approve", answers: answers.mapValues { [$0] }) } }.buttonStyle(.bordered).disabled(!relay.online || relay.current?.capabilities.canAnswer != true || (request.kind == "user_input" && (request.questions ?? []).contains { (answers[$0.id] ?? "").isEmpty }))
            }
            if request.kind != "unsupported" { Button("Rifiuta", role: .destructive) { Task { await relay.answer(request, decision: "reject") } }.disabled(!relay.online || relay.machines[request.machineId]?.status != "ONLINE" || relay.current?.capabilities.canAnswer != true) }
        }.padding().background(Color.orange.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
struct MCPRequestForm: View {
    @EnvironmentObject var relay: RelayController
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
        guard let schema else { return "Schema non disponibile: risolvi da Codex locale." }
        do { _ = try editJSON || !simple ? MCPResponse.parse(raw, schema: schema) : MCPResponse.fields(fields, schema: schema); return nil }
        catch { return error.localizedDescription }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let schema {
                DisclosureGroup("Schema MCP completo") { Text(schema.pretty).font(.caption.monospaced()).textSelection(.enabled) }
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
                                        Text("Seleziona…").tag("")
                                        ForEach(options.map { $0.string ?? $0.pretty }, id: \.self) { Text($0).tag($0) }
                                    }.pickerStyle(.menu)
                                } else if property["type"]?.string == "boolean" {
                                    Picker(key, selection: binding) { Text("Seleziona…").tag(""); Text("Sì").tag("true"); Text("No").tag("false") }.pickerStyle(.segmented)
                                } else if property["writeOnly"] == .bool(true) || property["format"] == .string("password") {
                                    SecureField(key, text: binding)
                                } else { TextField(key, text: binding).textInputAutocapitalization(.never).autocorrectionDisabled() }
                            }
                        }
                        Button("Modifica risposta come JSON") { raw = (try? MCPResponse.fields(fields, schema: schema))?.pretty ?? "{}"; editJSON = true }
                    } else {
                        Text("Risposta JSON conforme allo schema").font(.caption)
                        TextEditor(text: $raw).font(.body.monospaced()).frame(minHeight: 120).accessibilityLabel("Risposta MCP JSON")
                    }
                    if let validation { Text(validation).font(.caption).foregroundStyle(.orange) }
                    Button("Invia risposta MCP") { if let response { Task { await relay.answer(request, decision: "approve", content: response) } } }.buttonStyle(.bordered)
                        .disabled(response == nil || !relay.online || relay.machines[request.machineId]?.status != "ONLINE" || relay.current?.capabilities.canAnswer != true)
                } else { Text("Questo flusso MCP richiede Codex locale.").font(.caption) }
            } else { Text("Schema non disponibile: risolvi da Codex locale.").font(.caption) }
        }
    }
}
struct DevicesView: View {
    @EnvironmentObject var relay: RelayController
    @State private var add = false
    @State private var kind = "operator"
    @State private var name = "iPhone"
    @State private var machine = ""
    @State private var removing: MachineDevice?
    var body: some View {
        List {
            Section("Hub canonico") { Text(relay.credential?.hubUrl ?? "").font(.caption.monospaced()); Text("Un solo Hub · un’unica Fleet").foregroundStyle(.secondary) }
            #if canImport(UIKit)
            Section("Notifiche native") {
                Text(relay.nativePushAvailable ? relay.notificationStatus : "APNs non configurato sul Hub. Servono firma e capability Push Notifications Apple.").font(.caption).foregroundStyle(.secondary)
                Button("Abilita notifiche") { Task { await relay.enableNativePush() } }.disabled(!relay.nativePushAvailable)
                Button("Invia prova") { Task { await relay.testNativePush() } }.disabled(!relay.nativePushAvailable)
                Button("Disabilita notifiche") { Task { await relay.disableNativePush() } }
            }
            #endif
            Section("Macchine Codex") {
                ForEach(relay.registry?.machines ?? []) { device in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(device.machine.name) · \(device.machine.status)").font(.headline)
                        Text("\(device.access) · Codex \(device.machine.codexVersion ?? "—")").font(.caption)
                        if let account = device.machine.account { Text("\(account.email ?? account.kind) · \(account.plan ?? "")").font(.caption).foregroundStyle(.secondary) }
                        HStack {
                            if device.access != "REVOKED" { Button(device.access == "PAUSED" ? "Ricollega" : "Scollega") { Task { await relay.manageMachine(device.id, action: device.access == "PAUSED" ? "resume" : "pause") } }.buttonStyle(.bordered) }
                            Button("Elimina", role: .destructive) { removing = device }.buttonStyle(.bordered)
                        }
                    }.padding(.vertical, 4)
                }
                Text("Scollega sospende l’accesso Relay. Il lavoro Codex continua sulla macchina.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Client abbinati") {
                ForEach(relay.registry?.operators ?? []) { device in
                    VStack(alignment: .leading) {
                        Text(device.name + (device.id == relay.credential?.id ? " · questo iPhone" : ""))
                        Text(device.revoked ? "Accesso revocato" : "Accesso valido fino al \(device.expiresAt.prefix(10))").font(.caption).foregroundStyle(.secondary)
                        if !device.revoked { Button("Revoca accesso", role: .destructive) { Task { await relay.revokeDevice(device.id) } } }
                    }
                }
            }
            Section("Aggiungi dispositivo") {
                Picker("Tipo", selection: $kind) { Text("iPhone / operatore").tag("operator"); Text("Macchina Codex").tag("agent") }
                TextField("Nome", text: $name)
                if kind == "agent" { TextField("ID macchina (es. laptop)", text: $machine).textInputAutocapitalization(.never).autocorrectionDisabled() }
                Button("Genera codice monouso") { Task { await relay.createCode(kind: kind, name: name, machine: machine) } }.disabled(name.isEmpty || (kind == "agent" && machine.isEmpty))
                if let pair = relay.pairCode { Text(pair.code.prefix(4) + " " + pair.code.suffix(4)).font(.largeTitle.monospaced()).textSelection(.enabled); Text("Valido 5 minuti · una sola volta").font(.caption); if pair.kind == "agent" { Text("Sulla nuova macchina usa codex-relay pair --kind agent --hub-url URL --code-file FILE --out TOKEN. Poi installa l’agent.").font(.caption.monospaced()).textSelection(.enabled) } }
            }
            Section("Account ChatGPT") {
                Text("Qui vedi l’account utilizzato da Codex sulle macchine Relay. Le altre sessioni ChatGPT si gestiscono nelle impostazioni di sicurezza di ChatGPT.").font(.caption).foregroundStyle(.secondary)
                Link("Apri ChatGPT → Impostazioni → Sicurezza", destination: URL(string: "https://chatgpt.com/")!)
            }
            Section { Button("Esci e revoca questo accesso", role: .destructive) { Task { await relay.logout() } } }
        }.navigationTitle("Impostazioni").task { await relay.loadDevices() }
            .confirmationDialog("Eliminare \(removing?.machine.name ?? "") dal Hub? La credenziale verrà revocata; Codex continuerà localmente.", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) { Button("Elimina e revoca", role: .destructive) { if let id = removing?.id { Task { await relay.manageMachine(id, action: "remove") } }; removing = nil } }
    }
}
func statusLabel(_ status: String) -> String { ["OFFLINE": "Offline", "ALL": "All", "NEEDS_YOU": "Needs you", "WORKING": "Working", "READY": "Ready", "INACTIVE": "Inactive", "FAILED": "Failed"][status] ?? status }
func statusColor(_ status: String) -> Color { status == "NEEDS_YOU" ? .orange : status == "WORKING" ? .green : status == "FAILED" ? .red : .secondary }

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
    @StateObject private var relay: RelayController
    private let content: Content
    init(status: String = "WORKING", paired: Bool = true, @ViewBuilder content: () -> Content) {
        _relay = StateObject(wrappedValue: PreviewData.controller(status: status, paired: paired))
        self.content = content()
    }
    var body: some View { NavigationStack { content }.environmentObject(relay).preferredColorScheme(.dark).tint(.white) }
}
#Preview("Abbinamento · isolato") { RelayPreview(paired: false) { PairingView() } }
#Preview("Fleet · isolata") { RelayPreview { FleetView() } }
#Preview("Sessione · Ready") { RelayPreview(status: "READY") { SessionView() } }
#Preview("Sessione · Follow-up in coda") { RelayPreview { SessionView() } }
#Preview("Sessione · Needs You") { RelayPreview(status: "NEEDS_YOU") { SessionView() } }
#Preview("Dispositivi · isolati") { RelayPreview { DevicesView() } }
@MainActor private struct ConversationPreview: View {
    @StateObject private var relay = PreviewData.conversation()
    var body: some View { NavigationStack { SessionView() }.environmentObject(relay).preferredColorScheme(.dark).tint(.white) }
}
#Preview("Chat · riferimento iPhone") { ConversationPreview() }
#endif
