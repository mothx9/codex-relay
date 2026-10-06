import SwiftUI

struct RootView: View {
    @EnvironmentObject var relay: RelayController
    @State private var devices = false
    var body: some View {
        NavigationStack {
            Group { if relay.credential == nil { PairingView() } else { FleetView() } }
                .navigationTitle("CODEX RELAY").navigationBarTitleDisplayMode(.inline)
                .toolbar { if relay.credential != nil { ToolbarItem(placement: .topBarTrailing) { Button("Dispositivi", systemImage: "desktopcomputer") { devices = true } } } }
                .navigationDestination(isPresented: Binding(get: { !relay.selected.isEmpty }, set: { if !$0 { relay.closeDetail() } })) { SessionView() }
                .sheet(isPresented: $devices) { NavigationStack { DevicesView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { devices = false } } } } }
                .alert("Codex Relay", isPresented: Binding(get: { relay.error != nil }, set: { if !$0 { relay.error = nil } })) { Button("OK") { relay.error = nil } } message: { Text(relay.error ?? "") }
        }.tint(.white)
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
    private let statuses = ["ALL", "NEEDS_YOU", "WORKING", "READY", "INACTIVE", "FAILED"]
    var visible: [RelaySession] { relay.sessions.values.filter { (filter == "ALL" || $0.status == filter) && (search.isEmpty || "\($0.title) \($0.project) \($0.machineId)".localizedCaseInsensitiveContains(search)) }.sorted { $0.updatedAt > $1.updatedAt } }
    var body: some View {
        VStack(spacing: 0) {
            Text(relay.connection).font(.caption.monospaced()).foregroundStyle(relay.online ? .green : .secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal).accessibilityIdentifier("fleet.connection")
            ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(statuses, id: \.self) { value in
                Button { filter = value } label: { Text("\(statusLabel(value)) \(relay.sessions.values.filter { value == "ALL" || $0.status == value }.count)").font(.caption).padding(8).background(filter == value ? Color.white.opacity(0.13) : Color.clear).clipShape(RoundedRectangle(cornerRadius: 5)) }
            } }.padding(.horizontal) }
            List {
                ForEach(visible) { session in
                    Button { relay.open(session.id) } label: {
                        HStack(alignment: .top) {
                            Text(session.status == "NEEDS_YOU" ? "!" : "●").foregroundStyle(statusColor(session.status))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(relay.machines[session.machineId]?.name ?? session.machineId).font(.caption.monospaced()).foregroundStyle(.secondary)
                                Text(session.title).font(.headline).lineLimit(2)
                                Text(session.project).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(); Text(relay.machines[session.machineId]?.status == "ONLINE" ? statusLabel(session.status) : "Offline").font(.caption).foregroundStyle(statusColor(session.status))
                        }.foregroundStyle(.primary).padding(.vertical, 4)
                    }.accessibilityIdentifier("session." + session.id)
                }
                if visible.isEmpty { Text(relay.online ? "Nessuna sessione" : "Connessione al Hub…").foregroundStyle(.secondary) }
            }.listStyle(.plain)
        }.searchable(text: $search, prompt: "Sessione, macchina o progetto")
    }
}
struct SessionView: View {
    @EnvironmentObject var relay: RelayController
    @State private var draft = ""
    @State private var steer = false
    @State private var expectedTurn = ""
    @State private var interrupt = false
    var body: some View {
        if let session = relay.current {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("\(relay.machines[session.machineId]?.name ?? session.machineId) · \(session.project)").font(.caption.monospaced()).foregroundStyle(.secondary)
                    Text(session.title).font(.title2)
                    Text("\(statusLabel(session.status)) · \(relay.connection)").font(.caption).foregroundStyle(statusColor(session.status)).accessibilityIdentifier("session.connection")
                    DisclosureGroup("Contesto") { VStack(alignment: .leading) { Text(session.cwd); Text(session.branch ?? ""); Text(session.threadId) }.font(.caption.monospaced()).textSelection(.enabled) }
                    ForEach(relay.requests.values.filter { $0.sessionId == session.id }.sorted { $0.id < $1.id }) { PendingView(request: $0) }
                    ForEach(relay.chat.items) { activity in
                        VStack(alignment: .leading, spacing: 6) { Text(activity.kind == "userMessage" ? "ME" : activity.kind == "agentMessage" || activity.kind == "delta" ? "CODEX" : activity.kind.uppercased()).font(.caption.monospaced()).foregroundStyle(.secondary); Text(activity.text).font(.body.monospaced()).textSelection(.enabled).accessibilityIdentifier("activity." + activity.kind + "." + activity.id) }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(relay.outbox.visible(session: session.id)) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("ME · \(item.kind == "follow_up" ? "FOLLOW-UP" : item.kind == "steer" ? "STEER" : "NEW TURN") · \(item.phase.rawValue)").font(.caption.monospaced()).foregroundStyle(.secondary)
                            Text(item.text).textSelection(.enabled).accessibilityIdentifier("outbox." + item.id)
                            if item.phase == .failed {
                                Text(item.error ?? "Invio fallito").font(.caption).foregroundStyle(.orange)
                                if session.allows(item.kind) { Button(item.errorCode == "UNKNOWN_OUTCOME" ? "Ho verificato Codex: reinvia" : "Riprova") { Task { await relay.retry(item) } }.disabled(!relay.online) }
                                if item.kind == "steer", session.allows(session.defaultCommand) { Button("Invia come \(session.defaultCommand == "follow_up" ? "follow-up" : "nuovo turno")") { Task { await relay.retry(item, as: session.defaultCommand) } }.disabled(!relay.online) }
                                Button("Scarta") { relay.outbox.discard(item.id) }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if session.readOnly {
                        Text("Thread in sola lettura. Collegalo al daemon Codex per controllarlo.").font(.caption).foregroundStyle(.secondary)
                        Button("Collega thread") { Task { await relay.action("attach") } }.disabled(!relay.online)
                    }
                    if ["READY", "WORKING"].contains(session.status), !session.readOnly {
                        VStack(alignment: .leading) {
                            Text(steer ? "Steer modifica il lavoro ATTUALMENTE in corso." : session.status == "WORKING" ? "Codex eseguirà il follow-up dopo il lavoro corrente." : "Avvia un nuovo turno.").font(.caption).foregroundStyle(.secondary)
                            TextField(steer ? "Correggi il lavoro in corso…" : session.status == "WORKING" ? "Aggiungi un follow-up…" : "Scrivi a Codex…", text: $draft, axis: .vertical).lineLimit(2...8).padding(10).background(Color.white.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 6)).accessibilityIdentifier("composer.text")
                            Button(steer ? "Invia Steer" : session.status == "WORKING" ? "Invia follow-up" : "Invia") {
                                let text = draft; Task { if await relay.submit(text, kind: steer ? "steer" : nil, expectedTurn: steer ? expectedTurn : nil) { draft = ""; steer = false } }
                            }.buttonStyle(.borderedProminent).disabled(!relay.online || !session.allows(steer ? "steer" : session.defaultCommand) || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("composer.send")
                        }
                    }
                    DisclosureGroup("Azioni sul turno corrente") {
                        VStack(alignment: .leading) {
                            Button(steer ? "Torna al normale invio" : "Steer turno corrente") { steer.toggle(); expectedTurn = session.turnId ?? "" }.disabled(!steer && (!relay.online || !session.allows("steer")))
                            Button("Interrompi turno", role: .destructive) { interrupt = true }.disabled(!relay.online || !session.allows("interrupt"))
                        }
                    }
                    Text("Contesto effimero · cronologia in Codex").font(.caption).foregroundStyle(.secondary)
                }.padding()
            }.confirmationDialog("Interrompere il turno in corso?", isPresented: $interrupt, titleVisibility: .visible) { Button("Interrompi", role: .destructive) { Task { await relay.action("interrupt") } } }
        } else { Text("Sessione non disponibile") }
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
        }.navigationTitle("Dispositivi").task { await relay.loadDevices() }
            .confirmationDialog("Eliminare \(removing?.machine.name ?? "") dal Hub? La credenziale verrà revocata; Codex continuerà localmente.", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) { Button("Elimina e revoca", role: .destructive) { if let id = removing?.id { Task { await relay.manageMachine(id, action: "remove") } }; removing = nil } }
    }
}
func statusLabel(_ status: String) -> String { ["ALL": "All", "NEEDS_YOU": "Needs you", "WORKING": "Working", "READY": "Ready", "INACTIVE": "Inactive", "FAILED": "Failed"][status] ?? status }
func statusColor(_ status: String) -> Color { status == "NEEDS_YOU" ? .orange : status == "WORKING" ? .green : status == "FAILED" ? .red : .secondary }

#if DEBUG
// Explicitly sandboxed fixtures: no Keychain access, Hub transport or notification consent.
@MainActor private enum PreviewData {
    static func decode<T: Decodable>(_ text: String, as: T.Type = T.self) -> T {
        try! RelayJSON.decoder().decode(T.self, from: Data(text.utf8))
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
#endif
