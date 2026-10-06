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
    @Environment(RelayController.self) private var relay
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
    @Environment(RelayController.self) private var relay
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: typeSize.isAccessibilitySize ? 1 : 3), alignment: .leading, spacing: RelaySpacing.row) {
                            machineLabels
                        }
                    }.padding(.vertical, RelaySpacing.small)
                }.listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
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
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: sorted.filter { state($0) == "NEEDS_YOU" }.map(\.id).sorted())
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
            let active = relay.sessions.values.filter { $0.machineId == machine.id && ["WORKING", "NEEDS_YOU"].contains($0.status) }.count
            VStack(alignment: .leading, spacing: RelaySpacing.small) {
                HStack(spacing: 5) {
                    Image(systemName: online ? "checkmark.circle.fill" : "network.slash")
                        .foregroundStyle(online ? Color.accentColor : Color.secondary)
                    Text(machine.name).lineLimit(1)
                }.font(.caption.weight(.semibold))
                Text(online ? (active == 0 ? "Disponibile" : "\(active) in corso") : relay.machineConnectionLabel(machine.id))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }.frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(machine.name + ", " + relay.machineConnectionLabel(machine.id))
                .accessibilityValue(online ? (active == 0 ? "Nessun lavoro in corso" : "\(active) sessioni attive") : "")
                .accessibilityIdentifier("fleet.machine." + machine.id)
        }
    }
    @ViewBuilder private func sessionSection(_ title: String, sessions: [RelaySession]) -> some View {
        if !sessions.isEmpty {
            Section {
                ForEach(sessions) { FleetSessionRow(session: $0) }
            } header: {
                HStack {
                    Text(title)
                    Text("\(sessions.count)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                }.textCase(nil).font(.subheadline.weight(.semibold))
            }
        }
    }
}

struct FleetSessionRow: View {
    @Environment(RelayController.self) private var relay
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let session: RelaySession
    private var status: String { session.displayStatus(machine: relay.machines[session.machineId], connected: relay.online) }
    var body: some View {
        Button { relay.open(session.id) } label: {
            VStack(alignment: .leading, spacing: RelaySpacing.compact) {
                HStack(spacing: RelaySpacing.compact) {
                    Text(relay.machines[session.machineId]?.name ?? session.machineId).fontWeight(.semibold)
                    if !session.project.isEmpty { Text("·"); Text(session.project).lineLimit(1) }
                    Spacer(minLength: 4)
                    SessionStatusMark(status: status)
                }.font(.caption).foregroundStyle(.secondary)
                Text(session.title).font(.body.weight(.semibold)).lineLimit(2).foregroundStyle(.primary)
                HStack(alignment: .firstTextBaseline, spacing: RelaySpacing.compact) {
                    if status == "WORKING", let activity = relay.liveActivities[session.id] {
                        Text(activity.detail).lineLimit(1)
                            .contentTransition(.opacity)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: activity.itemId)
                    } else {
                        Text(status == "OFFLINE" ? relay.machineConnectionLabel(session.machineId) : statusLabel(status)).lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    if status == "WORKING" { ElapsedLabel(start: session.turnStarted) }
                }.font(.caption).foregroundStyle(.secondary)
            }.padding(.vertical, RelaySpacing.compact).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(RelayRowPressStyle()).alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .accessibilityIdentifier("session." + session.id)
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
            .accessibilityLabel(status == "OFFLINE" ? "Stato non aggiornato" : statusLabel(status))
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
                .multilineTextAlignment(.trailing).fixedSize().accessibilityLabel("Durata del turno").accessibilityValue(Text(date, style: .timer))
        }
    }
}

struct NeedsYouView: View {
    @Environment(RelayController.self) private var relay
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
                            if !relay.online || relay.machines[request.machineId]?.status != "ONLINE" { Text(relay.machineConnectionLabel(request.machineId)).font(.caption).foregroundStyle(.secondary) }
                        }.padding(.vertical, RelaySpacing.compact)
                    }.buttonStyle(.plain).accessibilityIdentifier("request." + request.id)
                }
            }
        }.listStyle(.insetGrouped)
    }
}
struct PendingView: View {
    @Environment(RelayController.self) private var relay
    let request: PendingRequest
    @State private var answers: [String: String] = [:]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(request.kind == "user_input" ? "Codex ha bisogno del tuo input" : request.kind == "command_approval" ? "Codex vuole eseguire" : request.kind == "file_approval" ? "Codex vuole modificare dei file" : request.kind == "permissions_approval" ? "Codex richiede un permesso" : "Codex richiede una decisione").font(.headline)
            Text("\(relay.machines[request.machineId]?.name ?? request.machineId) · \(relay.current?.project ?? "")").font(.caption).foregroundStyle(.secondary)
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
            if let progress = relay.requestProgress[request.presentationID] {
                Text(progress).font(.caption).foregroundStyle(.secondary)
            }
            if let error = relay.requestErrors[request.presentationID] {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
        }.padding().background(Color.orange.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 12))
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
    @Environment(RelayController.self) private var relay
    @State private var localSignOut = false
    @State private var revokeAccess = false
    var body: some View {
        List {
            Section {
                LabeledContent { Text(relay.online ? "Connesso" : "Non connesso").foregroundStyle(.secondary) } label: { Label("Hub", systemImage: "network") }
                NavigationLink { HubDetailsView() } label: { Label("Connessione e diagnostica", systemImage: "info.circle") }
                NavigationLink { NotificationSettingsView() } label: { Label("Notifiche", systemImage: "bell.badge") }
            }
            Section("Macchine") {
                ForEach(relay.registry?.machines ?? []) { device in
                    NavigationLink { MachineSettingsView(id: device.id) } label: {
                        HStack(spacing: RelaySpacing.row) {
                            Image(systemName: "desktopcomputer").foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: RelaySpacing.small) {
                                Text(device.machine.name)
                                Text(relay.machineConnectionLabel(device.id)).font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, RelaySpacing.small)
                    }
                }
                SettingsFeedback(id: "devices")
            }
            Section {
                Link(destination: URL(string: "https://chatgpt.com/")!) { Label("Account ChatGPT", systemImage: "person.crop.circle") }
            } footer: { Text("Gli account Codex sono visibili nei dettagli di ogni macchina. Le altre sessioni ChatGPT si gestiscono nelle impostazioni di sicurezza di ChatGPT.") }
            Section("Accesso") {
                ForEach(relay.registry?.operators ?? []) { device in
                    NavigationLink {
                        List {
                            LabeledContent("Dispositivo", value: device.name)
                            LabeledContent("Accesso", value: device.revoked ? "Revocato" : "Autorizzato")
                            LabeledContent("Scadenza", value: String(device.expiresAt.prefix(10)))
                            if !device.revoked {
                                Button("Revoca accesso", role: .destructive) { Task { await relay.revokeDevice(device.id) } }
                                    .disabled(relay.settingsProgress[device.id] != nil)
                            }
                            SettingsFeedback(id: device.id)
                        }.navigationTitle(device.name).navigationBarTitleDisplayMode(.inline)
                    } label: {
                        Label(device.name + (device.id == relay.credential?.id ? " · questo iPhone" : ""), systemImage: "iphone")
                    }
                }
                NavigationLink { EnrollmentView() } label: { Label("Abbina un dispositivo", systemImage: "plus.circle") }
            }
            Section {
                Button("Revoca questo accesso", role: .destructive) { revokeAccess = true }
                    .disabled(relay.settingsProgress["logout"] != nil)
                Button("Esci su questo iPhone", role: .destructive) { localSignOut = true }
                SettingsFeedback(id: "logout")
            } footer: { Text("La revoca disabilita la credenziale sul Hub. L’uscita locale rimuove soltanto l’accesso salvato su questo iPhone.") }
        }.navigationTitle("Impostazioni").task { await relay.loadDevices() }
            .confirmationDialog("Uscire su questo iPhone? La credenziale sul Hub rimarrà valida.", isPresented: $localSignOut, titleVisibility: .visible) {
                Button("Esci localmente", role: .destructive) { relay.forget() }
            }
            .confirmationDialog("Revocare l’accesso di questo iPhone sul Hub? Per rientrare servirà un nuovo abbinamento.", isPresented: $revokeAccess, titleVisibility: .visible) {
                Button("Revoca ed esci", role: .destructive) { Task { await relay.logout() } }
            }
    }
}

private struct SettingsFeedback: View {
    @Environment(RelayController.self) private var relay
    let id: String
    var body: some View {
        if let progress = relay.settingsProgress[id] { ProgressView(progress).font(.caption) }
        if let error = relay.settingsErrors[id] { Text(error).font(.caption).foregroundStyle(.orange) }
    }
}

private struct HubDetailsView: View {
    @Environment(RelayController.self) private var relay
    var body: some View {
        List {
            LabeledContent("Connessione", value: relay.online ? "Attiva" : relay.connection)
            Section("Hub") { Text(relay.credential?.hubUrl ?? "").font(.footnote).textSelection(.enabled) }
            Section { Text("La cronologia appartiene a Codex. Relay mantiene il contesto della conversazione soltanto in memoria.").font(.footnote).foregroundStyle(.secondary) }
        }.navigationTitle("Connessione").navigationBarTitleDisplayMode(.inline)
    }
}

private struct MachineSettingsView: View {
    @Environment(RelayController.self) private var relay
    let id: String
    @State private var removing = false
    var body: some View {
        List {
            if let device = relay.registry?.machines.first(where: { $0.id == id }) {
                Section {
                    LabeledContent("Relay", value: relay.machineConnectionLabel(id))
                    LabeledContent("Codex", value: device.machine.codexVersion ?? "Non disponibile")
                    if let account = device.machine.account {
                        LabeledContent("Account", value: account.email ?? account.kind)
                        if let plan = account.plan { LabeledContent("Piano", value: plan) }
                    }
                }
                Section {
                    if device.access != "REVOKED" {
                        Button(device.access == "PAUSED" ? "Riprendi Relay" : "Metti in pausa Relay") {
                            Task { await relay.manageMachine(id, action: device.access == "PAUSED" ? "resume" : "pause") }
                        }.disabled(relay.settingsProgress[id] != nil)
                    }
                    SettingsFeedback(id: id)
                } footer: { Text("La pausa sospende solo il collegamento a Relay. Il lavoro Codex continua sulla macchina.") }
                Section {
                    Button("Rimuovi macchina e revoca credenziale", role: .destructive) { removing = true }
                        .disabled(relay.settingsProgress[id] != nil)
                }
            } else { Text("Macchina rimossa dal Hub.").foregroundStyle(.secondary) }
        }.navigationTitle(relay.machines[id]?.name ?? id).navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Rimuovere questa macchina dal Hub e revocare la credenziale? Codex continuerà localmente.", isPresented: $removing, titleVisibility: .visible) {
                Button("Rimuovi e revoca", role: .destructive) { Task { await relay.manageMachine(id, action: "remove") } }
            }
    }
}

private struct EnrollmentView: View {
    @Environment(RelayController.self) private var relay
    @State private var kind = "operator"
    @State private var name = "iPhone"
    @State private var machine = ""
    var body: some View {
        Form {
            Section {
                Picker("Tipo", selection: $kind) { Text("iPhone / operatore").tag("operator"); Text("Macchina Codex").tag("agent") }
                TextField("Nome", text: $name)
                if kind == "agent" { TextField("ID macchina", text: $machine).textInputAutocapitalization(.never).autocorrectionDisabled() }
                Button("Genera codice monouso") { Task { await relay.createCode(kind: kind, name: name, machine: machine) } }
                    .disabled(name.isEmpty || (kind == "agent" && machine.isEmpty) || relay.settingsProgress["pairing"] != nil)
                SettingsFeedback(id: "pairing")
            }
            if let pair = relay.pairCode {
                Section {
                    Text(pair.code.prefix(4) + " " + pair.code.suffix(4)).font(.title.monospaced()).textSelection(.enabled)
                    Text("Valido 5 minuti · una sola volta").font(.caption).foregroundStyle(.secondary)
                    if pair.kind == "agent" { Text("Sulla nuova macchina usa codex-relay pair con questo codice, poi installa l’agent.").font(.footnote) }
                }
            }
        }.navigationTitle("Abbina dispositivo").navigationBarTitleDisplayMode(.inline)
    }
}

private struct NotificationSettingsView: View {
    @Environment(RelayController.self) private var relay
    var body: some View {
        List {
            Section("Disponibilità") {
                LabeledContent("Permesso iOS", value: relay.notificationPermission)
                LabeledContent("APNs sul Hub", value: relay.nativePushAvailable ? "Configurato" : "Non configurato")
                LabeledContent("Token Apple", value: relay.apnsToken == nil ? "Non ottenuto" : "Ottenuto")
                LabeledContent("Registrazione Relay", value: relay.pushRegistered ? "Confermata" : "Non verificata")
            }
            Section {
                Button("Abilita notifiche") { Task { await relay.enableNativePush() } }.disabled(!relay.nativePushAvailable)
                Button("Invia prova") { Task { await relay.testNativePush() } }.disabled(!relay.nativePushAvailable || !relay.pushRegistered)
                Button("Disabilita notifiche") { Task { await relay.disableNativePush() } }
                Text(relay.notificationStatus).font(.caption).foregroundStyle(.secondary)
            } footer: { if !relay.nativePushAvailable { Text("Il collegamento a Codex resta attivo. Le notifiche push richiedono APNs sul Hub e la capability Apple Push Notifications, non disponibile con Personal Team.") } }
        }.navigationTitle("Notifiche").navigationBarTitleDisplayMode(.inline).task { await relay.refreshNotificationPermission() }
    }
}
func statusLabel(_ status: String) -> String { ["OFFLINE": "Relay non connesso", "ALL": "Tutte", "NEEDS_YOU": "Serve una risposta", "WORKING": "In corso", "READY": "Pronta", "INACTIVE": "Inattiva", "FAILED": "Errore"][status] ?? status }
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
    @State private var relay: RelayController
    private let content: Content
    init(status: String = "WORKING", paired: Bool = true, @ViewBuilder content: () -> Content) {
        _relay = State(initialValue: PreviewData.controller(status: status, paired: paired))
        self.content = content()
    }
    var body: some View { NavigationStack { content }.environment(relay).preferredColorScheme(.dark).tint(.white) }
}
#Preview("Abbinamento · isolato") { RelayPreview(paired: false) { PairingView() } }
#Preview("Fleet · isolata") { RelayPreview { FleetView() } }
#Preview("Sessione · Ready") { RelayPreview(status: "READY") { SessionView() } }
#Preview("Sessione · Follow-up in coda") { RelayPreview { SessionView() } }
#Preview("Sessione · Needs You") { RelayPreview(status: "NEEDS_YOU") { SessionView() } }
#Preview("Dispositivi · isolati") { RelayPreview { DevicesView() } }
@MainActor private struct ConversationPreview: View {
    @State private var relay = PreviewData.conversation()
    var body: some View { NavigationStack { SessionView() }.environment(relay).preferredColorScheme(.dark).tint(.white) }
}
#Preview("Chat · riferimento iPhone") { ConversationPreview() }
#endif
