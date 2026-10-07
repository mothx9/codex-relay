import SwiftUI

struct MachinesView: View {
    @Environment(RelayController.self) private var relay
    var body: some View {
        List {
            ForEach(relay.machines.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { machine in
                NavigationLink { MachineSettingsView(id: machine.id) } label: {
                    HStack(spacing: RelaySpacing.row) {
                        Image(systemName: "desktopcomputer").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: RelaySpacing.small) {
                            Text(machine.name).font(.body.weight(.medium))
                            Text(relay.machineConnectionLabel(machine.id)).font(.caption).foregroundStyle(.secondary)
                            if machine.status != "ONLINE", let date = RelayDate.parse(machine.lastSeen) {
                                Text("Last seen \(date, style: .relative) ago").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        SessionStatusMark(status: relay.online ? machine.status : "OFFLINE")
                    }.padding(.vertical, RelaySpacing.small)
                }.accessibilityIdentifier("machine." + machine.id)
            }
            if relay.machines.isEmpty { ContentUnavailableView("Add your first machine", systemImage: "desktopcomputer", description: Text("Enroll a Relay Agent from Settings to see your Codex sessions here.")) }
        }.navigationTitle("Machines").navigationBarTitleDisplayMode(.inline)
            .task { await relay.loadDevices() }
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
            Section("Your Relay") {
                NavigationLink { MachinesView() } label: { Label("Machines", systemImage: "desktopcomputer") }
                NavigationLink { AccountsView() } label: { Label("Codex Accounts", systemImage: "person.crop.circle") }
                SettingsFeedback(id: "devices")
            }
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
            Section("Tempi osservati") {
                LabeledContent("Campioni ricevuti", value: "\(relay.receiptTiming.samples)")
                LabeledContent("Hub → iPhone", value: relay.receiptTiming.clockSkew ? "Orologi non allineati" : relay.receiptTiming.samples == 0 ? "In attesa di campioni" : String(format: "%.1f ms", relay.receiptTiming.hubToNativeMs)).accessibilityIdentifier("diagnostics.transport")
                LabeledContent("Applicazione stato", value: String(format: "%.1f ms", relay.receiptTiming.reducerMs)).accessibilityIdentifier("diagnostics.reducer")
                Text(relay.receiptTiming.clockSkew ? "Orologi non allineati: latenza non confrontabile." : "La stima tra dispositivi include lo scarto degli orologi. Non misura il tempo del modello né il rendering.").font(.caption).foregroundStyle(.secondary)
            }
            Section { Text("La cronologia appartiene a Codex. Relay mantiene il contesto della conversazione soltanto in memoria.").font(.footnote).foregroundStyle(.secondary) }
        }.navigationTitle("Connessione").navigationBarTitleDisplayMode(.inline)
    }
}

struct MachineSettingsView: View {
    @Environment(RelayController.self) private var relay
    let id: String
    @State private var removing = false
    var body: some View {
        List {
            if let device = relay.registry?.machines.first(where: { $0.id == id }) {
                Section {
                    LabeledContent("Relay", value: relay.machineConnectionLabel(id))
                    LabeledContent("Codex", value: device.machine.codexVersion ?? "Non disponibile")
                    if let machine = relay.machines[id], let freshness = machine.freshness {
                        LabeledContent("Agent", value: machine.agentVersion ?? "Non disponibile")
                        LabeledContent("Snapshot Codex", value: String(format: "%.1f ms", freshness.snapshotMs ?? 0))
                        LabeledContent("Connessione → Online", value: String(format: "%.1f ms", freshness.syncMs ?? 0))
                        LabeledContent("Riconnessioni", value: "\(freshness.reconnectCount ?? 0)")
                        LabeledContent("Sequenza", value: "\(freshness.sequence ?? 0)")
                    }
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
