import SwiftUI

struct DevicesView: View {
    @Environment(RelayController.self) private var relay
    var body: some View {
        List {
            Section {
                NavigationLink { HubDetailsView() } label: {
                    Label { VStack(alignment: .leading, spacing: RelaySpacing.small) {
                        Text(String(localized: "Your Relay", bundle: relayLocalizationBundle))
                        if !relay.online { Text(String(localized: "Hub not connected", bundle: relayLocalizationBundle)).font(.caption).foregroundStyle(.secondary) }
                    } } icon: { Image(systemName: "network") }
                }.accessibilityIdentifier("settings.hub")
            }
            Section(String(localized: "This iPhone", bundle: relayLocalizationBundle)) {
                NavigationLink { NotificationSettingsView() } label: { Label(String(localized: "Notifications", bundle: relayLocalizationBundle), systemImage: "bell.badge") }
            }
            Section {
                NavigationLink { AboutView() } label: { Label(String(localized: "About Codex Relay", bundle: relayLocalizationBundle), systemImage: "info.circle") }
            }
        }.navigationTitle(String(localized: "Settings", bundle: relayLocalizationBundle)).navigationBarTitleDisplayMode(.inline).task { await relay.loadDevices() }
    }
}

struct MachinesView: View {
    var machineIDs: Set<String>? = nil
    @Environment(RelayController.self) private var relay
    var body: some View {
        List {
            ForEach(relay.machines.values.filter { machineIDs?.contains($0.id) ?? true }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { machine in
                NavigationLink { MachineSettingsView(id: machine.id) } label: {
                    HStack(spacing: RelaySpacing.row) {
                        Image(systemName: "desktopcomputer").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: RelaySpacing.small) {
                            Text(machine.name).font(.body.weight(.medium))
                            Text(relay.machineConnectionLabel(machine.id)).font(.caption).foregroundStyle(.secondary)
                            if machine.status != "ONLINE", let date = RelayDate.parse(machine.lastSeen) {
                                HStack(spacing: 4) { Text(String(localized: "Last seen", bundle: relayLocalizationBundle)); Text(date, style: .relative) }.font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        SessionStatusMark(status: relay.online ? machine.status : "OFFLINE")
                    }.padding(.vertical, RelaySpacing.small)
                }.accessibilityIdentifier("machine." + machine.id)
            }
            Section {
                NavigationLink { EnrollmentView(initialKind: "agent") } label: { Label(String(localized: "Add a machine", bundle: relayLocalizationBundle), systemImage: "plus.circle") }
                SettingsFeedback(id: "devices")
            } footer: {
                Text(String(localized: "An Agent connects a machine’s local Codex runtime to your Hub. Relay connectivity is separate from the work running on that machine.", bundle: relayLocalizationBundle))
            }
        }.navigationTitle(String(localized: "Machines", bundle: relayLocalizationBundle)).navigationBarTitleDisplayMode(.inline)
            .task { await relay.loadDevices() }.refreshable { await relay.loadDevices() }
    }
}

private struct SettingsFeedback: View {
    @Environment(RelayController.self) private var relay
    let id: String
    var body: some View {
        if let progress = relay.settingsProgress[id] { ProgressView(progress).font(.caption) }
        if let error = relay.settingsErrors[id] { Text(error).font(.caption).foregroundStyle(RelayPalette.attention).accessibilityIdentifier("settings.error." + id) }
    }
}

private struct HubDetailsView: View {
    @Environment(RelayController.self) private var relay
    var body: some View {
        List {
            Section {
                LabeledContent("Hub", value: relay.online ? String(localized: "Connected", bundle: relayLocalizationBundle) : String(localized: "Not connected", bundle: relayLocalizationBundle))
                Text(relay.credential?.hubUrl ?? "").font(.footnote).textSelection(.enabled)
            } header: { Text(String(localized: "Self-hosted installation", bundle: relayLocalizationBundle)) } footer: {
                Text(String(localized: "Your Hub coordinates machines, controllers and notifications. The person administering the Hub owns this installation. There is no Relay cloud account.", bundle: relayLocalizationBundle))
            }
            Section(String(localized: "Source of truth", bundle: relayLocalizationBundle)) {
                Label(String(localized: "Codex owns conversations and queued work", bundle: relayLocalizationBundle), systemImage: "text.bubble")
                Label(String(localized: "The Hub owns Relay access and routing", bundle: relayLocalizationBundle), systemImage: "network")
                Text(String(localized: "Conversation content is fetched from Codex and held temporarily in memory, not stored as a Relay transcript.", bundle: relayLocalizationBundle)).font(.footnote).foregroundStyle(.secondary)
            }
            Section { NavigationLink(String(localized: "Controllers & recovery", bundle: relayLocalizationBundle)) { ControllersView() } }
        }.navigationTitle(String(localized: "Your Relay", bundle: relayLocalizationBundle)).navigationBarTitleDisplayMode(.inline)
    }
}

struct MachineSettingsView: View {
    @Environment(RelayController.self) private var relay
    let id: String
    @State private var removing = false
    @State private var revoking = false
    var body: some View {
        List {
            if let machine = relay.machines[id] {
                let device = relay.registry?.machines.first(where: { $0.id == id })
                Section(String(localized: "Connection", bundle: relayLocalizationBundle)) {
                    LabeledContent("Relay", value: relay.machineConnectionLabel(id))
                    DateFact(title: String(localized: "Last seen", bundle: relayLocalizationBundle), value: machine.lastSeen)
                    LabeledContent(String(localized: "Access", bundle: relayLocalizationBundle), value: device?.access == "REVOKED" ? String(localized: "Revoked", bundle: relayLocalizationBundle) : device?.access == "PAUSED" ? String(localized: "Paused", bundle: relayLocalizationBundle) : device == nil ? String(localized: "Not verified", bundle: relayLocalizationBundle) : String(localized: "Authorized", bundle: relayLocalizationBundle))
                }
                Section("Runtime") {
                    LabeledContent("Codex", value: machine.codexVersion ?? String(localized: "Unavailable", bundle: relayLocalizationBundle))
                    LabeledContent("Agent", value: machine.agentVersion ?? String(localized: "Unavailable", bundle: relayLocalizationBundle))
                    LabeledContent(String(localized: "Known sessions", bundle: relayLocalizationBundle), value: "\(relay.fleetSessions.values.filter { $0.machineId == id }.count)")
                    if let entry = relay.accounts.first(where: { $0.machines.contains(id) }) {
                        NavigationLink { AccountDetailView(id: entry.id) } label: {
                            LabeledContent(String(localized: "Codex account", bundle: relayLocalizationBundle), value: entry.account.email ?? entry.account.kind)
                        }
                    } else if let account = machine.account { LabeledContent(String(localized: "Codex account", bundle: relayLocalizationBundle), value: account.email ?? account.kind) }
                }
                Section {
                    NavigationLink(String(localized: "Machine diagnostics", bundle: relayLocalizationBundle)) { MachineDiagnosticsView(id: id) }
                }
                if let device {
                    Section {
                        if device.access != "REVOKED" {
                            Button(device.access == "PAUSED" ? String(localized: "Resume Relay Agent", bundle: relayLocalizationBundle) : String(localized: "Pause Relay Agent", bundle: relayLocalizationBundle)) {
                                Task { await relay.manageMachine(id, action: device.access == "PAUSED" ? "resume" : "pause") }
                            }.disabled(relay.settingsProgress[id] != nil)
                        }
                        SettingsFeedback(id: id)
                    } footer: { Text(String(localized: "Pause stops Relay access only. Local Codex work continues. Unresolved requests remain last-known until the Agent reconnects.", bundle: relayLocalizationBundle)) }
                    Section(String(localized: "Access", bundle: relayLocalizationBundle)) {
                        if device.access != "REVOKED" {
                            Button(String(localized: "Revoke machine credential", bundle: relayLocalizationBundle), role: .destructive) { revoking = true }.disabled(relay.settingsProgress[id] != nil)
                        }
                        Button(String(localized: "Remove machine enrollment", bundle: relayLocalizationBundle), role: .destructive) { removing = true }.disabled(relay.settingsProgress[id] != nil)
                    }
                }
            } else { ContentUnavailableView(String(localized: "Machine unavailable", bundle: relayLocalizationBundle), systemImage: "desktopcomputer.trianglebadge.exclamationmark", description: Text(String(localized: "This machine is not in the current Hub snapshot.", bundle: relayLocalizationBundle))) }
        }.navigationTitle(relay.machines[id]?.name ?? String(localized: "Machine", bundle: relayLocalizationBundle)).navigationBarTitleDisplayMode(.inline)
            .task { await relay.loadDevices(); await relay.loadAccounts() }
            .confirmationDialog(String(localized: "Revoke this machine’s Relay credential? Its last-known state remains, but reconnecting requires a new enrollment. Local Codex work continues.", bundle: relayLocalizationBundle), isPresented: $revoking, titleVisibility: .visible) {
                Button(String(localized: "Revoke credential", bundle: relayLocalizationBundle), role: .destructive) { Task { await relay.manageMachine(id, action: "revoke") } }
            }
            .confirmationDialog(String(localized: "Remove this enrollment and its Relay routing metadata? The credential is revoked. Codex and its history remain on the machine.", bundle: relayLocalizationBundle), isPresented: $removing, titleVisibility: .visible) {
                Button(String(localized: "Remove enrollment", bundle: relayLocalizationBundle), role: .destructive) { Task { await relay.manageMachine(id, action: "remove") } }
            }
    }
}

private struct DateFact: View {
    let title: String
    let value: String?
    var body: some View {
        LabeledContent(title) {
            if let date = RelayDate.parse(value) { Text(date, style: .relative).accessibilityLabel(Text(date, style: .date) + Text(" ") + Text(date, style: .time)) }
            else { Text(String(localized: "Unavailable", bundle: relayLocalizationBundle)) }
        }
    }
}
struct FreshnessRows: View {
    let freshness: MachineFreshness
    var body: some View {
        if let protocolVersion = freshness.protocolVersion { LabeledContent(String(localized: "Relay protocol", bundle: relayLocalizationBundle), value: "\(protocolVersion)") }
        if let ms = freshness.snapshotMs { LabeledContent(String(localized: "Codex snapshot", bundle: relayLocalizationBundle), value: String(format: "%.1f ms", ms)) }
        if let ms = freshness.syncMs { LabeledContent(String(localized: "Connection → Online", bundle: relayLocalizationBundle), value: String(format: "%.1f ms", ms)) }
        if let count = freshness.reconnectCount { LabeledContent(String(localized: "Reconnects", bundle: relayLocalizationBundle), value: "\(count)") }
        if let sequence = freshness.sequence { LabeledContent(String(localized: "Event sequence", bundle: relayLocalizationBundle), value: "\(sequence)") }
        if let sequence = freshness.snapshotSequence { LabeledContent(String(localized: "Snapshot watermark", bundle: relayLocalizationBundle), value: "\(sequence)") }
        if let epoch = freshness.epoch { LabeledContent(String(localized: "Agent epoch", bundle: relayLocalizationBundle)) { Text(epoch).font(.caption.monospaced()).textSelection(.enabled) } }
        if let reason = freshness.lastDisconnectReason { LabeledContent(String(localized: "Last disconnect", bundle: relayLocalizationBundle), value: reason) }
        if let timing = freshness.agentToHub {
            LabeledContent("Agent → Hub", value: timing.clockSkew ? String(localized: "Clocks not comparable", bundle: relayLocalizationBundle) : timing.samples == 0 ? String(localized: "No samples", bundle: relayLocalizationBundle) : String(localized: "\(timing.meanMs.formatted(.number.precision(.fractionLength(1)))) ms mean", bundle: relayLocalizationBundle))
        }
    }
}

struct ControllersView: View {
    @Environment(RelayController.self) private var relay
    @State private var localSignOut = false
    @State private var revokeAccess = false
    var body: some View {
        List {
            Section {
                Text(String(localized: "The Hub administrator owns this installation and manages recovery. All authorized controllers have the same Relay permissions.", bundle: relayLocalizationBundle)).font(.footnote).foregroundStyle(.secondary)
            }
            Section(String(localized: "Authorized controllers", bundle: relayLocalizationBundle)) {
                ForEach(relay.registry?.operators ?? []) { device in
                    NavigationLink { ControllerDetailView(id: device.id) } label: {
                        VStack(alignment: .leading, spacing: RelaySpacing.small) {
                            Label(device.name, systemImage: device.id == relay.credential?.id ? "iphone" : "rectangle.connected.to.line.below")
                            Text(device.revoked ? String(localized: "Revoked", bundle: relayLocalizationBundle) : (RelayDate.parse(device.expiresAt) ?? .distantPast) < Date() ? String(localized: "Expired", bundle: relayLocalizationBundle) : device.id == relay.credential?.id ? String(localized: "This iPhone", bundle: relayLocalizationBundle) : String(localized: "Authorized controller", bundle: relayLocalizationBundle)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                NavigationLink { EnrollmentView(initialKind: "operator") } label: { Label(String(localized: "Pair another controller", bundle: relayLocalizationBundle), systemImage: "plus.circle") }
                SettingsFeedback(id: "devices")
            }
            Section(String(localized: "Recovery", bundle: relayLocalizationBundle)) {
                Text(String(localized: "If you lose access to every controller, create a new pairing code on the Hub host. Keep the bootstrap credential on that host.", bundle: relayLocalizationBundle)).font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Button(String(localized: "Revoke this iPhone’s access", bundle: relayLocalizationBundle), role: .destructive) { revokeAccess = true }.disabled(relay.settingsProgress["logout"] != nil)
                Button(String(localized: "Sign out locally", bundle: relayLocalizationBundle), role: .destructive) { localSignOut = true }
                SettingsFeedback(id: "logout")
            } footer: { Text(String(localized: "Revocation disables the credential on the Hub. Local sign-out only removes this iPhone’s saved credential and does not claim server revocation.", bundle: relayLocalizationBundle)) }
        }.navigationTitle(String(localized: "Controllers & Access", bundle: relayLocalizationBundle)).navigationBarTitleDisplayMode(.inline)
            .task { await relay.loadDevices() }.refreshable { await relay.loadDevices() }
            .confirmationDialog(String(localized: "Sign out locally? The Hub credential remains valid until revoked or expired.", bundle: relayLocalizationBundle), isPresented: $localSignOut, titleVisibility: .visible) {
                Button(String(localized: "Sign out locally", bundle: relayLocalizationBundle), role: .destructive) { relay.forget() }
            }
            .confirmationDialog(String(localized: "Revoke this iPhone on the Hub? You will need a new pairing code to return.", bundle: relayLocalizationBundle), isPresented: $revokeAccess, titleVisibility: .visible) {
                Button(String(localized: "Revoke and sign out", bundle: relayLocalizationBundle), role: .destructive) { Task { await relay.logout() } }
            }
    }
}

private struct ControllerDetailView: View {
    @Environment(RelayController.self) private var relay
    let id: String
    @State private var action: String?
    var body: some View {
        List {
            if let device = relay.registry?.operators.first(where: { $0.id == id }) {
                Section {
                    LabeledContent("Controller", value: device.name)
                    LabeledContent(String(localized: "Access", bundle: relayLocalizationBundle), value: device.revoked ? String(localized: "Revoked", bundle: relayLocalizationBundle) : (RelayDate.parse(device.expiresAt) ?? .distantPast) < Date() ? String(localized: "Expired", bundle: relayLocalizationBundle) : String(localized: "Authorized", bundle: relayLocalizationBundle))
                    DateFact(title: String(localized: "Paired", bundle: relayLocalizationBundle), value: device.createdAt)
                    DateFact(title: String(localized: "Last seen", bundle: relayLocalizationBundle), value: device.lastSeen)
                    if let date = RelayDate.parse(device.expiresAt) { LabeledContent(String(localized: "Expires", bundle: relayLocalizationBundle)) { Text(date, style: .date) } }
                }
                Section {
                    if !device.revoked { Button(String(localized: "Revoke access", bundle: relayLocalizationBundle), role: .destructive) { action = "revoke" } }
                    Button(String(localized: "Remove controller", bundle: relayLocalizationBundle), role: .destructive) { action = "remove" }
                    SettingsFeedback(id: id)
                }.disabled(relay.settingsProgress[id] != nil)
            } else { Text(String(localized: "This controller has been removed.", bundle: relayLocalizationBundle)) }
        }.navigationTitle("Controller").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(action == "remove" ? String(localized: "Remove this controller and its notification registration? Its credential will stop working.", bundle: relayLocalizationBundle) : String(localized: "Revoke this controller’s access immediately?", bundle: relayLocalizationBundle), isPresented: Binding(get: { action != nil }, set: { if !$0 { action = nil } }), titleVisibility: .visible) {
                Button(action == "remove" ? String(localized: "Remove controller", bundle: relayLocalizationBundle) : String(localized: "Revoke access", bundle: relayLocalizationBundle), role: .destructive) {
                    let chosen = action; action = nil
                    Task { if chosen == "remove" { await relay.removeController(id) } else { await relay.revokeDevice(id) } }
                }
            }
    }
}

private struct EnrollmentView: View {
    @Environment(RelayController.self) private var relay
    @State private var kind: String
    @State private var name = ""
    @State private var machine = ""
    init(initialKind: String) { _kind = State(initialValue: initialKind) }
    var body: some View {
        Form {
            Section {
                Picker(String(localized: "Device", bundle: relayLocalizationBundle), selection: $kind) { Text("Controller").tag("operator"); Text(String(localized: "Machine Agent", bundle: relayLocalizationBundle)).tag("agent") }.disabled(relay.settingsProgress["pairing"] != nil)
                TextField(String(localized: "Name", bundle: relayLocalizationBundle), text: $name).disabled(relay.settingsProgress["pairing"] != nil)
                if kind == "agent" { TextField(String(localized: "Machine ID", bundle: relayLocalizationBundle), text: $machine).disabled(relay.settingsProgress["pairing"] != nil).textInputAutocapitalization(.never).autocorrectionDisabled() }
                Button(String(localized: "Create one-time code", bundle: relayLocalizationBundle)) { Task { await relay.createCode(kind: kind, name: name, machine: machine) } }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (kind == "agent" && machine.isEmpty) || relay.settingsProgress["pairing"] != nil)
                SettingsFeedback(id: "pairing")
            } footer: { Text(kind == "agent" ? String(localized: "Enter this code on the machine using codex-relay pair. The Agent connects outbound to your Hub.", bundle: relayLocalizationBundle) : String(localized: "Enter the Hub URL and this code on the other iPhone. The code grants controller access to this Relay.", bundle: relayLocalizationBundle)) }
            if let pair = relay.pairCode, pair.kind == kind, !name.isEmpty, kind != "agent" || pair.machine == machine {
                Section(String(localized: "One-time pairing code", bundle: relayLocalizationBundle)) {
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        if let expires = RelayDate.parse(pair.expiresAt), expires > timeline.date {
                            Text(pair.code.prefix(4) + " " + pair.code.suffix(4)).font(.title.monospaced()).textSelection(.enabled)
                            (Text(String(localized: "Expires in ", bundle: relayLocalizationBundle)) + Text(expires, style: .timer)).font(.caption).foregroundStyle(.secondary)
                        } else { Label(String(localized: "Code expired. Create a new one.", bundle: relayLocalizationBundle), systemImage: "clock.badge.exclamationmark").foregroundStyle(RelayPalette.attention) }
                    }
                    Text(String(localized: "Redeem once. Keep this code private.", bundle: relayLocalizationBundle)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }.navigationTitle(kind == "agent" ? String(localized: "Add machine", bundle: relayLocalizationBundle) : String(localized: "Pair controller", bundle: relayLocalizationBundle)).navigationBarTitleDisplayMode(.inline)
            .onAppear { relay.pairCode = nil }
            .onDisappear { relay.pairCode = nil }
            .onChange(of: kind) { _, _ in relay.pairCode = nil }
            .onChange(of: name) { _, _ in relay.pairCode = nil }
            .onChange(of: machine) { _, _ in relay.pairCode = nil }
    }
}

private struct NotificationSettingsView: View {
    @Environment(RelayController.self) private var relay
    @Environment(\.openURL) private var openURL
    var body: some View {
        List {
            Section {
                LabeledContent(String(localized: "Local alerts", bundle: relayLocalizationBundle), value: relay.notificationReadiness.localReady ? String(localized: "Ready", bundle: relayLocalizationBundle) : !relay.notificationsEnabled ? String(localized: "Off", bundle: relayLocalizationBundle) : !relay.notificationAllowed ? relay.notificationPermission : String(localized: "Connect to Relay", bundle: relayLocalizationBundle))
                LabeledContent(String(localized: "Remote push", bundle: relayLocalizationBundle), value: relay.notificationReadiness.remoteReady ? String(localized: "Registered", bundle: relayLocalizationBundle) : String(localized: "Setup required", bundle: relayLocalizationBundle))
            } footer: {
                Text(String(localized: "Local alerts work while this app is connected. Remote push uses APNs to reach you when the app is suspended or closed.", bundle: relayLocalizationBundle))
            }
            Section {
                if !relay.notificationsEnabled || !relay.notificationAllowed {
                    Button(String(localized: "Allow notifications", bundle: relayLocalizationBundle)) { Task { await relay.enableNativePush() } }
                        .disabled(relay.settingsProgress["notifications"] != nil)
                }
                Button(String(localized: "Test local alert", bundle: relayLocalizationBundle)) { relay.testLocalNotification() }
                    .disabled(!relay.notificationReadiness.localReady).accessibilityIdentifier("notifications.testLocal")
                Button(String(localized: "Test remote push", bundle: relayLocalizationBundle)) { Task { await relay.testNativePush() } }
                    .disabled(!relay.notificationReadiness.remoteReady || relay.settingsProgress["notifications"] != nil)
                if relay.notificationsEnabled {
                    Button(String(localized: "Disable Relay notifications", bundle: relayLocalizationBundle)) { Task { await relay.disableNativePush() } }
                        .disabled(relay.settingsProgress["notifications"] != nil)
                }
                Button(String(localized: "Open iOS notification settings", bundle: relayLocalizationBundle)) { if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) } }
                SettingsFeedback(id: "notifications"); SettingsFeedback(id: "localAlerts")
            } footer: {
                Text(String(localized: "Needs You, live questions, completion, failure and machines offline after a grace period. Previews omit conversation content. Completion is quiet in the session you are reading.", bundle: relayLocalizationBundle))
            }
            Section {
                DisclosureGroup(String(localized: "Delivery details", bundle: relayLocalizationBundle)) {
                    LabeledContent(String(localized: "iOS permission", bundle: relayLocalizationBundle), value: relay.notificationPermission)
                    LabeledContent(String(localized: "Hub APNs", bundle: relayLocalizationBundle), value: relay.nativePushAvailable ? String(localized: "Configured", bundle: relayLocalizationBundle) : String(localized: "Not configured", bundle: relayLocalizationBundle))
                    LabeledContent(String(localized: "Apple device token", bundle: relayLocalizationBundle), value: relay.apnsToken == nil ? String(localized: "Not obtained", bundle: relayLocalizationBundle) : String(localized: "Obtained", bundle: relayLocalizationBundle))
                    LabeledContent(String(localized: "Relay registration", bundle: relayLocalizationBundle), value: relay.pushRegistrationVerifiedAt == nil ? String(localized: "Not verified", bundle: relayLocalizationBundle) : relay.pushRegistered ? String(localized: "Registered", bundle: relayLocalizationBundle) : String(localized: "Not registered", bundle: relayLocalizationBundle))
                    if let verified = relay.pushRegistrationVerifiedAt { LabeledContent(String(localized: "Last checked", bundle: relayLocalizationBundle)) { Text(verified, style: .relative) } }
                    Text(relay.notificationStatus).font(.caption).foregroundStyle(.secondary)
                    SettingsFeedback(id: "pushRegistration")
                }
            }
            if !relay.nativePushAvailable {
                Section { Text(String(localized: "APNs must be configured on the Hub. The signed iPhone app also needs the Apple Push Notifications capability, unavailable with Personal Team provisioning. Relay control works independently.", bundle: relayLocalizationBundle)).font(.footnote).foregroundStyle(.secondary)
                    Link(String(localized: "Set up Hub notifications", bundle: relayLocalizationBundle), destination: URL(string: "https://github.com/mothx9/codex-relay/blob/main/docs/setup/notifications.md")!)
                }
            }
        }.navigationTitle(String(localized: "Notifications", bundle: relayLocalizationBundle)).navigationBarTitleDisplayMode(.inline)
            .task { await relay.refreshNativePush() }.refreshable { await relay.refreshNativePush() }
    }
}

struct DiagnosticsView: View {
    @Environment(RelayController.self) private var relay
    @State private var copied = false
    var body: some View {
        List {
            Section("Relay") {
                LabeledContent("App", value: AboutView.version)
                LabeledContent(String(localized: "Hub connection", bundle: relayLocalizationBundle), value: relay.online ? String(localized: "Connected", bundle: relayLocalizationBundle) : String(localized: "Not connected", bundle: relayLocalizationBundle))
                if let diagnostics = relay.diagnostics {
                    LabeledContent(String(localized: "Hub version", bundle: relayLocalizationBundle), value: diagnostics.hubVersion)
                    LabeledContent(String(localized: "Protocol", bundle: relayLocalizationBundle), value: "\(diagnostics.protocolVersion)")
                    if let database = diagnostics.database { LabeledContent("Database", value: database == "reachable" ? String(localized: "Reachable", bundle: relayLocalizationBundle) : String(localized: "Unavailable", bundle: relayLocalizationBundle)) }
                }
                if let updated = relay.diagnosticsUpdatedAt { LabeledContent(String(localized: "Checked", bundle: relayLocalizationBundle)) { Text(updated, style: .relative) } }
                SettingsFeedback(id: "diagnostics")
            }
            Section(String(localized: "System health", bundle: relayLocalizationBundle)) {
                NavigationLink { MachinesView() } label: {
                    LabeledContent(String(localized: "Machines", bundle: relayLocalizationBundle), value: "\(relay.machines.count)")
                }
                LabeledContent(String(localized: "Pending requests", bundle: relayLocalizationBundle), value: "\(relay.requests.count)")
                if let registry = relay.registry { LabeledContent(String(localized: "Controllers", bundle: relayLocalizationBundle), value: "\(registry.operators.count)") }
                if let diagnostics = relay.diagnostics {
                    LabeledContent(String(localized: "Reconnects", bundle: relayLocalizationBundle), value: "\(diagnostics.machines.reduce(0) { $0 + ($1.freshness.reconnectCount ?? 0) })")
                }
                LabeledContent(String(localized: "Hub APNs", bundle: relayLocalizationBundle), value: relay.nativePushAvailable ? String(localized: "Configured", bundle: relayLocalizationBundle) : String(localized: "Not configured", bundle: relayLocalizationBundle))
                let unavailable = relay.machines.values.filter { $0.status != "ONLINE" }.count
                if unavailable > 0 { Label(unavailable == 1 ? String(localized: "1 machine needs attention", bundle: relayLocalizationBundle) : String(localized: "\(unavailable) machines need attention", bundle: relayLocalizationBundle), systemImage: "exclamationmark.circle").foregroundStyle(RelayPalette.attention) }
            }
            Section(String(localized: "Observed latency", bundle: relayLocalizationBundle)) {
                LabeledContent(String(localized: "Samples", bundle: relayLocalizationBundle), value: "\(relay.receiptTiming.samples)")
                LabeledContent("Hub → iPhone", value: relay.receiptTiming.clockSkew ? String(localized: "Clocks not comparable", bundle: relayLocalizationBundle) : relay.receiptTiming.samples == 0 ? String(localized: "No samples", bundle: relayLocalizationBundle) : String(format: "%.1f ms", relay.receiptTiming.hubToNativeMs)).accessibilityIdentifier("diagnostics.transport")
                LabeledContent(String(localized: "State reducer", bundle: relayLocalizationBundle), value: relay.receiptTiming.samples == 0 ? String(localized: "No samples", bundle: relayLocalizationBundle) : String(format: "%.1f ms", relay.receiptTiming.reducerMs)).accessibilityIdentifier("diagnostics.reducer")
                Text(String(localized: "Cross-host estimates include clock offset. These values do not measure model execution or rendering.", bundle: relayLocalizationBundle)).font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button(copied ? String(localized: "Copied", bundle: relayLocalizationBundle) : String(localized: "Copy Diagnostics", bundle: relayLocalizationBundle), systemImage: copied ? "checkmark" : "doc.on.doc") {
                    guard let report = relay.diagnostics?.redactedReport(appVersion: AboutView.version, hubConnected: relay.online) else { return }
                    UIPasteboard.general.string = report + "\nHub APNs configured: \(relay.nativePushAvailable)\nThis controller registered for push: \(relay.pushRegistered)\nNative event samples: \(relay.receiptTiming.samples)\nHub to native estimate ms: \(relay.receiptTiming.clockSkew ? "clocks not comparable" : String(format: "%.1f", relay.receiptTiming.hubToNativeMs))"
                    copied = true
                }.disabled(relay.diagnostics == nil).accessibilityIdentifier("diagnostics.copy")
            } footer: { Text(String(localized: "Copied diagnostics omit machine names, host addresses, account identities, credentials and conversation content.", bundle: relayLocalizationBundle)) }
        }.navigationTitle(String(localized: "Diagnostics", bundle: relayLocalizationBundle)).navigationBarTitleDisplayMode(.inline)
            .task { await relay.loadDiagnostics(); await relay.loadDevices() }.refreshable { copied = false; await relay.loadDiagnostics() }
    }
}

private struct AboutView: View {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? String(localized: "Unavailable", bundle: relayLocalizationBundle) }
    var body: some View {
        List {
            Section { Image("RelayMark").resizable().scaledToFit().frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 16)).accessibilityHidden(true); Text("Codex Relay").font(.title2.weight(.semibold)); Text(String(localized: "Supervise and continue Codex across your machines from iPhone.", bundle: relayLocalizationBundle)).foregroundStyle(.secondary); LabeledContent(String(localized: "Version", bundle: relayLocalizationBundle), value: Self.version) }
            Section { Link(String(localized: "Source & documentation", bundle: relayLocalizationBundle), destination: URL(string: "https://github.com/mothx9/codex-relay")!); Text(String(localized: "Self-hosted. Open source. Independent of OpenAI.", bundle: relayLocalizationBundle)).font(.footnote).foregroundStyle(.secondary) }
        }.navigationTitle(String(localized: "About", bundle: relayLocalizationBundle)).navigationBarTitleDisplayMode(.inline)
    }
}

struct RelayLibraryView: View {
    let openHistory: () -> Void
    var body: some View {
        List {
            Section(String(localized: "Browse", bundle: relayLocalizationBundle)) {
                NavigationLink { MachinesView() } label: { Label(String(localized: "Machines", bundle: relayLocalizationBundle), systemImage: "desktopcomputer") }
                NavigationLink { AccountsView() } label: { Label(String(localized: "Codex Accounts", bundle: relayLocalizationBundle), systemImage: "person.crop.circle") }
                Button(action: openHistory) { Label(String(localized: "All sessions", bundle: relayLocalizationBundle), systemImage: "clock.arrow.circlepath") }
            }
            Section(String(localized: "Manage", bundle: relayLocalizationBundle)) {
                NavigationLink { ControllersView() } label: { Label(String(localized: "Controllers & Access", bundle: relayLocalizationBundle), systemImage: "lock.shield") }
                NavigationLink { DiagnosticsView() } label: { Label(String(localized: "Diagnostics", bundle: relayLocalizationBundle), systemImage: "waveform.path.ecg") }
                NavigationLink { DevicesView() } label: { Label(String(localized: "Settings", bundle: relayLocalizationBundle), systemImage: "gearshape") }
            }
        }.navigationTitle("Relay").navigationBarTitleDisplayMode(.inline)
    }
}

struct MachineDiagnosticsView: View {
    @Environment(RelayController.self) private var relay
    let id: String
    var body: some View {
        List {
            if let host = relay.machines[id] {
                Section {
                    LabeledContent("Relay", value: relay.machineConnectionLabel(id))
                    LabeledContent("Agent", value: host.agentVersion ?? String(localized: "Unavailable", bundle: relayLocalizationBundle))
                    LabeledContent("Codex", value: host.codexVersion ?? String(localized: "Unavailable", bundle: relayLocalizationBundle))
                    DateFact(title: String(localized: "Last seen", bundle: relayLocalizationBundle), value: host.lastSeen)
                }
                if let freshness = host.freshness {
                    Section(String(localized: "Freshness", bundle: relayLocalizationBundle)) {
                        DateFact(title: String(localized: "Last heartbeat", bundle: relayLocalizationBundle), value: freshness.lastHeartbeat)
                        DateFact(title: String(localized: "Last event", bundle: relayLocalizationBundle), value: freshness.lastEvent)
                        DateFact(title: String(localized: "Last snapshot", bundle: relayLocalizationBundle), value: freshness.lastSnapshot)
                        FreshnessRows(freshness: freshness)
                    }
                }
                if let diagnostic = relay.diagnostics?.machines.first(where: { $0.id == id }) {
                    Section {
                        LabeledContent("Adapter", value: diagnostic.adapter)
                        LabeledContent(String(localized: "Known sessions", bundle: relayLocalizationBundle), value: "\(diagnostic.sessions)")
                        LabeledContent(String(localized: "Hot sessions", bundle: relayLocalizationBundle), value: "\(diagnostic.hot)")
                        LabeledContent(String(localized: "Pending requests", bundle: relayLocalizationBundle), value: "\(diagnostic.pending)")
                        if let age = diagnostic.snapshotAgeMs { LabeledContent(String(localized: "Snapshot age at check", bundle: relayLocalizationBundle), value: "\(age / 1000) s") }
                    }
                }
            }
        }.navigationTitle(String(localized: "Machine diagnostics", bundle: relayLocalizationBundle)).navigationBarTitleDisplayMode(.inline)
            .task { await relay.loadDiagnostics() }.refreshable { await relay.loadDiagnostics() }
    }
}
