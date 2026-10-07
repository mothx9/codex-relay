import SwiftUI

struct DevicesView: View {
    @Environment(RelayController.self) private var relay
    var body: some View {
        List {
            Section {
                NavigationLink { HubDetailsView() } label: {
                    Label { VStack(alignment: .leading, spacing: RelaySpacing.small) {
                        Text("Your Relay")
                        Text(relay.online ? "Connected to your Hub" : "Hub not connected").font(.caption).foregroundStyle(.secondary)
                    } } icon: { Image(systemName: "network") }
                }.accessibilityIdentifier("settings.hub")
            }
            Section("Fleet") {
                NavigationLink { MachinesView() } label: { Label("Machines", systemImage: "desktopcomputer") }
                NavigationLink { AccountsView() } label: { Label("Codex Accounts", systemImage: "person.crop.circle") }
            }
            Section("This iPhone") {
                NavigationLink { NotificationSettingsView() } label: { Label("Notifications", systemImage: "bell.badge") }
                NavigationLink { ControllersView() } label: { Label("Controllers & Access", systemImage: "lock.shield") }
            }
            Section {
                NavigationLink { DiagnosticsView() } label: { Label("Diagnostics", systemImage: "waveform.path.ecg") }
                NavigationLink { AboutView() } label: { Label("About Codex Relay", systemImage: "info.circle") }
            }
        }.navigationTitle("Settings").task { await relay.loadDevices() }
    }
}

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
            Section {
                NavigationLink { EnrollmentView(initialKind: "agent") } label: { Label("Add a machine", systemImage: "plus.circle") }
                SettingsFeedback(id: "devices")
            } footer: {
                Text("An Agent connects a machine’s local Codex runtime to your Hub. Relay connectivity is separate from the work running on that machine.")
            }
        }.navigationTitle("Machines").navigationBarTitleDisplayMode(.inline)
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
                LabeledContent("Hub", value: relay.online ? "Connected" : "Not connected")
                Text(relay.credential?.hubUrl ?? "").font(.footnote).textSelection(.enabled)
            } header: { Text("Self-hosted installation") } footer: {
                Text("Your Hub coordinates machines, controllers and notifications. The person administering the Hub owns this installation. There is no Relay cloud account.")
            }
            Section("Source of truth") {
                Label("Codex owns conversations and queued work", systemImage: "text.bubble")
                Label("The Hub owns Relay access and routing", systemImage: "network")
                Text("Conversation content is fetched from Codex and held temporarily in memory, not stored as a Relay transcript.").font(.footnote).foregroundStyle(.secondary)
            }
            Section { NavigationLink("Controllers & recovery") { ControllersView() } }
        }.navigationTitle("Your Relay").navigationBarTitleDisplayMode(.inline)
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
                Section("Connection") {
                    LabeledContent("Relay", value: relay.machineConnectionLabel(id))
                    DateFact(title: "Last seen", value: machine.lastSeen)
                    LabeledContent("Access", value: device?.access == "REVOKED" ? "Revoked" : device?.access == "PAUSED" ? "Paused" : device == nil ? "Not verified" : "Authorized")
                }
                Section("Runtime") {
                    LabeledContent("Codex", value: machine.codexVersion ?? "Unavailable")
                    LabeledContent("Agent", value: machine.agentVersion ?? "Unavailable")
                    LabeledContent("Known sessions", value: "\(relay.fleetSessions.values.filter { $0.machineId == id }.count)")
                    if let entry = relay.accounts.first(where: { $0.machines.contains(id) }) {
                        NavigationLink { AccountDetailView(id: entry.id) } label: {
                            LabeledContent("Codex account", value: entry.account.email ?? entry.account.kind)
                        }
                    } else if let account = machine.account { LabeledContent("Codex account", value: account.email ?? account.kind) }
                }
                if let freshness = machine.freshness {
                    Section("Freshness") {
                        DateFact(title: "Last heartbeat", value: freshness.lastHeartbeat)
                        DateFact(title: "Last event", value: freshness.lastEvent)
                        DateFact(title: "Last snapshot", value: freshness.lastSnapshot)
                        DisclosureGroup("Connection diagnostics") { FreshnessRows(freshness: freshness) }
                    }
                }
                if let device {
                    Section {
                        if device.access != "REVOKED" {
                            Button(device.access == "PAUSED" ? "Resume Relay Agent" : "Pause Relay Agent") {
                                Task { await relay.manageMachine(id, action: device.access == "PAUSED" ? "resume" : "pause") }
                            }.disabled(relay.settingsProgress[id] != nil)
                        }
                        SettingsFeedback(id: id)
                    } footer: { Text("Pause stops Relay access only. Local Codex work continues. Unresolved requests remain last-known until the Agent reconnects.") }
                    Section("Access") {
                        if device.access != "REVOKED" {
                            Button("Revoke machine credential", role: .destructive) { revoking = true }.disabled(relay.settingsProgress[id] != nil)
                        }
                        Button("Remove machine enrollment", role: .destructive) { removing = true }.disabled(relay.settingsProgress[id] != nil)
                    }
                }
            } else { ContentUnavailableView("Machine unavailable", systemImage: "desktopcomputer.trianglebadge.exclamationmark", description: Text("This machine is not in the current Hub snapshot.")) }
        }.navigationTitle(relay.machines[id]?.name ?? "Machine").navigationBarTitleDisplayMode(.inline)
            .task { await relay.loadDevices(); await relay.loadAccounts() }
            .confirmationDialog("Revoke this machine’s Relay credential? Its last-known state remains, but reconnecting requires a new enrollment. Local Codex work continues.", isPresented: $revoking, titleVisibility: .visible) {
                Button("Revoke credential", role: .destructive) { Task { await relay.manageMachine(id, action: "revoke") } }
            }
            .confirmationDialog("Remove this enrollment and its Relay routing metadata? The credential is revoked. Codex and its history remain on the machine.", isPresented: $removing, titleVisibility: .visible) {
                Button("Remove enrollment", role: .destructive) { Task { await relay.manageMachine(id, action: "remove") } }
            }
    }
}

private struct DateFact: View {
    let title: String
    let value: String?
    var body: some View {
        LabeledContent(title) {
            if let date = RelayDate.parse(value) { Text(date, style: .relative).accessibilityLabel(Text(date, style: .date) + Text(" ") + Text(date, style: .time)) }
            else { Text("Unavailable") }
        }
    }
}
private struct FreshnessRows: View {
    let freshness: MachineFreshness
    var body: some View {
        if let protocolVersion = freshness.protocolVersion { LabeledContent("Relay protocol", value: "\(protocolVersion)") }
        if let ms = freshness.snapshotMs { LabeledContent("Codex snapshot", value: String(format: "%.1f ms", ms)) }
        if let ms = freshness.syncMs { LabeledContent("Connection → Online", value: String(format: "%.1f ms", ms)) }
        if let count = freshness.reconnectCount { LabeledContent("Reconnects", value: "\(count)") }
        if let sequence = freshness.sequence { LabeledContent("Event sequence", value: "\(sequence)") }
        if let sequence = freshness.snapshotSequence { LabeledContent("Snapshot watermark", value: "\(sequence)") }
        if let epoch = freshness.epoch { LabeledContent("Agent epoch") { Text(epoch).font(.caption.monospaced()).textSelection(.enabled) } }
        if let reason = freshness.lastDisconnectReason { LabeledContent("Last disconnect", value: reason) }
        if let timing = freshness.agentToHub {
            LabeledContent("Agent → Hub", value: timing.clockSkew ? "Clocks not comparable" : timing.samples == 0 ? "No samples" : String(format: "%.1f ms mean", timing.meanMs))
        }
    }
}

private struct ControllersView: View {
    @Environment(RelayController.self) private var relay
    @State private var localSignOut = false
    @State private var revokeAccess = false
    var body: some View {
        List {
            Section {
                Text("The Hub administrator owns this installation and manages recovery. All authorized controllers have the same Relay permissions.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Authorized controllers") {
                ForEach(relay.registry?.operators ?? []) { device in
                    NavigationLink { ControllerDetailView(id: device.id) } label: {
                        VStack(alignment: .leading, spacing: RelaySpacing.small) {
                            Label(device.name, systemImage: device.id == relay.credential?.id ? "iphone" : "rectangle.connected.to.line.below")
                            Text(device.revoked ? "Revoked" : (RelayDate.parse(device.expiresAt) ?? .distantPast) < Date() ? "Expired" : device.id == relay.credential?.id ? "This iPhone" : "Authorized controller").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                NavigationLink { EnrollmentView(initialKind: "operator") } label: { Label("Pair another controller", systemImage: "plus.circle") }
                SettingsFeedback(id: "devices")
            }
            Section("Recovery") {
                Text("If you lose access to every controller, create a new pairing code on the Hub host. Keep the bootstrap credential on that host.").font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Button("Revoke this iPhone’s access", role: .destructive) { revokeAccess = true }.disabled(relay.settingsProgress["logout"] != nil)
                Button("Sign out locally", role: .destructive) { localSignOut = true }
                SettingsFeedback(id: "logout")
            } footer: { Text("Revocation disables the credential on the Hub. Local sign-out only removes this iPhone’s saved credential and does not claim server revocation.") }
        }.navigationTitle("Controllers & Access").navigationBarTitleDisplayMode(.inline)
            .task { await relay.loadDevices() }.refreshable { await relay.loadDevices() }
            .confirmationDialog("Sign out locally? The Hub credential remains valid until revoked or expired.", isPresented: $localSignOut, titleVisibility: .visible) {
                Button("Sign out locally", role: .destructive) { relay.forget() }
            }
            .confirmationDialog("Revoke this iPhone on the Hub? You will need a new pairing code to return.", isPresented: $revokeAccess, titleVisibility: .visible) {
                Button("Revoke and sign out", role: .destructive) { Task { await relay.logout() } }
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
                    LabeledContent("Access", value: device.revoked ? "Revoked" : (RelayDate.parse(device.expiresAt) ?? .distantPast) < Date() ? "Expired" : "Authorized")
                    DateFact(title: "Paired", value: device.createdAt)
                    DateFact(title: "Last seen", value: device.lastSeen)
                    if let date = RelayDate.parse(device.expiresAt) { LabeledContent("Expires") { Text(date, style: .date) } }
                }
                Section {
                    if !device.revoked { Button("Revoke access", role: .destructive) { action = "revoke" } }
                    Button("Remove controller", role: .destructive) { action = "remove" }
                    SettingsFeedback(id: id)
                }.disabled(relay.settingsProgress[id] != nil)
            } else { Text("This controller has been removed.") }
        }.navigationTitle("Controller").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(action == "remove" ? "Remove this controller and its notification registration? Its credential will stop working." : "Revoke this controller’s access immediately?", isPresented: Binding(get: { action != nil }, set: { if !$0 { action = nil } }), titleVisibility: .visible) {
                Button(action == "remove" ? "Remove controller" : "Revoke access", role: .destructive) {
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
                Picker("Device", selection: $kind) { Text("Controller").tag("operator"); Text("Machine Agent").tag("agent") }
                TextField("Name", text: $name)
                if kind == "agent" { TextField("Machine ID", text: $machine).textInputAutocapitalization(.never).autocorrectionDisabled() }
                Button("Create one-time code") { Task { await relay.createCode(kind: kind, name: name, machine: machine) } }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (kind == "agent" && machine.isEmpty) || relay.settingsProgress["pairing"] != nil)
                SettingsFeedback(id: "pairing")
            } footer: { Text(kind == "agent" ? "Enter this code on the machine using codex-relay pair. The Agent connects outbound to your Hub." : "Enter the Hub URL and this code on the other iPhone. The code grants controller access to this Relay.") }
            if let pair = relay.pairCode, pair.kind == kind {
                Section("One-time pairing code") {
                    Text(pair.code.prefix(4) + " " + pair.code.suffix(4)).font(.title.monospaced()).textSelection(.enabled)
                    Text("Expires after 5 minutes. Redeem once.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }.navigationTitle(kind == "agent" ? "Add machine" : "Pair controller").navigationBarTitleDisplayMode(.inline)
            .onDisappear { relay.pairCode = nil }
    }
}

private struct NotificationSettingsView: View {
    @Environment(RelayController.self) private var relay
    @Environment(\.openURL) private var openURL
    var body: some View {
        List {
            Section("Availability") {
                LabeledContent("iOS permission", value: relay.notificationPermission)
                LabeledContent("Hub APNs", value: relay.nativePushAvailable ? "Configured" : "Not configured")
                LabeledContent("Apple device token", value: relay.apnsToken == nil ? "Not obtained" : "Obtained")
                LabeledContent("Relay registration", value: relay.pushRegistrationVerifiedAt == nil ? "Not verified" : relay.pushRegistered ? "Registered" : "Not registered")
                if let verified = relay.pushRegistrationVerifiedAt { LabeledContent("Last checked") { Text(verified, style: .relative) } }
            }
            Section {
                Button("Allow notifications") { Task { await relay.enableNativePush() } }
                Button("Send test notification") { Task { await relay.testNativePush() } }.disabled(!relay.nativePushAvailable || !relay.pushRegistered)
                Button("Disable Relay notifications") { Task { await relay.disableNativePush() } }
                Button("Open iOS notification settings") { if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) } }
                Text(relay.notificationStatus).font(.caption).foregroundStyle(.secondary)
                SettingsFeedback(id: "notifications"); SettingsFeedback(id: "pushRegistration")
            } footer: {
                Text("Needs You, completion, failure and machines offline after a grace period. No notifications for individual commands or tokens. Lock-screen previews omit project and conversation content by default.")
            }.disabled(relay.settingsProgress["notifications"] != nil || relay.settingsProgress["pushRegistration"] != nil)
            if !relay.nativePushAvailable {
                Section { Text("APNs must be configured on the Hub. The signed iPhone app also needs the Apple Push Notifications capability, unavailable with Personal Team provisioning. Relay control works independently.").font(.footnote).foregroundStyle(.secondary) }
            }
        }.navigationTitle("Notifications").navigationBarTitleDisplayMode(.inline)
            .task { await relay.refreshNativePush() }.refreshable { await relay.refreshNativePush() }
    }
}

private struct DiagnosticsView: View {
    @Environment(RelayController.self) private var relay
    @State private var copied = false
    var body: some View {
        List {
            Section("Relay") {
                LabeledContent("App", value: AboutView.version)
                LabeledContent("Hub connection", value: relay.online ? "Connected" : "Not connected")
                if let diagnostics = relay.diagnostics {
                    LabeledContent("Hub version", value: diagnostics.hubVersion)
                    LabeledContent("Protocol", value: "\(diagnostics.protocolVersion)")
                    if let database = diagnostics.database { LabeledContent("Database", value: database == "reachable" ? "Reachable" : "Unavailable") }
                }
                if let updated = relay.diagnosticsUpdatedAt { LabeledContent("Checked") { Text(updated, style: .relative) } }
                SettingsFeedback(id: "diagnostics")
            }
            Section("Observed latency") {
                LabeledContent("Samples", value: "\(relay.receiptTiming.samples)")
                LabeledContent("Hub → iPhone", value: relay.receiptTiming.clockSkew ? "Clocks not comparable" : relay.receiptTiming.samples == 0 ? "No samples" : String(format: "%.1f ms", relay.receiptTiming.hubToNativeMs)).accessibilityIdentifier("diagnostics.transport")
                LabeledContent("State reducer", value: String(format: "%.1f ms", relay.receiptTiming.reducerMs)).accessibilityIdentifier("diagnostics.reducer")
                Text("Cross-host estimates include clock offset. These values do not measure model execution or rendering.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(relay.diagnostics?.machines ?? []) { machine in
                Section(relay.machines[machine.id]?.name ?? "Machine") {
                    LabeledContent("Snapshot state", value: statusLabel(machine.state))
                    LabeledContent("Known sessions", value: "\(machine.sessions)")
                    LabeledContent("Hot sessions", value: "\(machine.hot)")
                    LabeledContent("Pending requests", value: "\(machine.pending)")
                    if let age = machine.snapshotAgeMs { LabeledContent("Snapshot age at check", value: "\(age / 1000) s") }
                    DisclosureGroup("Details") { FreshnessRows(freshness: machine.freshness) }
                }
            }
            Section {
                Button(copied ? "Copied" : "Copy Diagnostics", systemImage: copied ? "checkmark" : "doc.on.doc") {
                    guard let report = relay.diagnostics?.redactedReport(appVersion: AboutView.version, hubConnected: relay.online) else { return }
                    UIPasteboard.general.string = report + "\nHub APNs configured: \(relay.nativePushAvailable)\nThis controller registered for push: \(relay.pushRegistered)\nNative event samples: \(relay.receiptTiming.samples)\nHub to native estimate ms: \(relay.receiptTiming.clockSkew ? "clocks not comparable" : String(format: "%.1f", relay.receiptTiming.hubToNativeMs))"
                    copied = true
                }.disabled(relay.diagnostics == nil).accessibilityIdentifier("diagnostics.copy")
            } footer: { Text("Copied diagnostics omit machine names, host addresses, account identities, credentials and conversation content.") }
        }.navigationTitle("Diagnostics").navigationBarTitleDisplayMode(.inline)
            .task { await relay.loadDiagnostics() }.refreshable { copied = false; await relay.loadDiagnostics() }
    }
}

private struct AboutView: View {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unavailable" }
    var body: some View {
        List {
            Section { Text("Codex Relay").font(.title2.weight(.semibold)); Text("Supervise and continue Codex across your machines from iPhone.").foregroundStyle(.secondary); LabeledContent("Version", value: Self.version) }
            Section { Link("Source & documentation", destination: URL(string: "https://github.com/mothx9/codex-relay")!); Text("Self-hosted. Open source. Independent of OpenAI.").font(.footnote).foregroundStyle(.secondary) }
        }.navigationTitle("About").navigationBarTitleDisplayMode(.inline)
    }
}
