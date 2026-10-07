import SwiftUI

/// Shared semantic roles; content remains opaque, glass is reserved for controls.
enum RelayPalette {
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let working = Color(uiColor: .systemGreen)
    static let attention = Color(uiColor: .systemOrange)
    static let failure = Color(uiColor: .systemRed)
    static let terminal = Color(uiColor: .systemCyan)
    static let tool = Color(uiColor: .systemPurple)
    static let file = Color(uiColor: .systemOrange)
    static let addition = Color(uiColor: .systemGreen)
    static let deletion = Color(uiColor: .systemRed)
    static func status(_ value: String) -> Color {
        switch value {
        case "WORKING": working
        case "NEEDS_YOU": attention
        case "FAILED": failure
        default: .secondary
        }
    }
}

struct FleetView: View {
    @Environment(RelayController.self) private var relay
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var filter: String
    @Binding var machine: String
    @Binding var search: String
    @State private var showingMachines = false
    private var browsingAll: Bool { !search.isEmpty || filter != "ALL" }
    private var sorted: [RelaySession] {
        relay.fleetSessions.values.filter { machine.isEmpty || $0.machineId == machine }
            .sorted { $0.updatedAt == $1.updatedAt ? $0.id < $1.id : $0.updatedAt > $1.updatedAt }
    }
    private func state(_ session: RelaySession) -> String {
        session.displayStatus(machine: relay.machines[session.machineId], connected: relay.online)
    }
    private var visible: [RelaySession] {
        sorted.filter {
            (filter == "ALL" || filter == "HISTORY" || state($0) == filter)
            && (search.isEmpty || "\($0.title) \($0.project) \($0.machineId)".localizedCaseInsensitiveContains(search))
        }
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if search.isEmpty { fleetHeader }
                if !browsingAll {
                    sessionSection("Serve una risposta", symbol: "bubble.left.and.exclamationmark.bubble.right", sessions: sorted.filter { state($0) == "NEEDS_YOU" }, tint: RelayPalette.attention)
                    sessionSection("In corso", symbol: "waveform.path", sessions: sorted.filter { state($0) == "WORKING" }, tint: RelayPalette.working)
                    sessionSection("Recenti", symbol: "clock", sessions: Array(sorted.filter { !["WORKING", "NEEDS_YOU"].contains(state($0)) }.prefix(6)), tint: .secondary)
                    Button { filter = "HISTORY" } label: {
                        HStack {
                            Label("Tutte le sessioni", systemImage: "clock.arrow.circlepath")
                            Spacer()
                            Text("\(sorted.count)").monospacedDigit().foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        }.font(.subheadline.weight(.medium)).padding(16)
                            .background(RelayPalette.surface, in: RoundedRectangle(cornerRadius: 18))
                    }.buttonStyle(RelayRowPressStyle()).accessibilityIdentifier("fleet.history")
                } else {
                    sessionSection(filter == "HISTORY" || filter == "ALL" ? "Sessioni" : statusLabel(filter), symbol: "line.3.horizontal", sessions: visible, tint: .secondary)
                    if visible.isEmpty { ContentUnavailableView.search(text: search) }
                    if filter == "HISTORY" || !search.isEmpty { catalogueControls }
                }
            }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 24)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Sessione, macchina o progetto", text: $search)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("fleet.search")
                if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.accessibilityLabel("Clear search").frame(minWidth: 44, minHeight: 44) }
            }.padding(.horizontal, 16).frame(minHeight: 48).modifier(SearchChrome())
                .padding(.horizontal, RelaySpacing.page).padding(.vertical, 8)
        }
        .background(RelayPalette.canvas)
        .sheet(isPresented: $showingMachines) {
            NavigationStack {
                MachinesView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { showingMachines = false }.accessibilityIdentifier("machines.close") } }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: sorted.filter { state($0) == "NEEDS_YOU" }.map(\.id).sorted())
    }

    private var fleetHeader: some View {
        VStack(alignment: .leading, spacing: RelaySpacing.compact) {
            let waiting = relay.requests.count
            let working = relay.sessions.values.filter { state($0) == "WORKING" }.count
            Text(waiting > 0 ? "\(waiting) needs you · \(working) working" : working > 0 ? "\(working) sessions working" : "Your fleet, at a glance")
                .font(.title3.weight(.semibold)).accessibilityIdentifier("fleet.summary")
            Button { showingMachines = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: relay.online ? "network" : "network.slash")
                    Text(relay.online ? "\(relay.machines.values.filter { $0.status == "ONLINE" }.count)/\(relay.machines.count) machines online" : "Connecting to Hub…")
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                }.font(.subheadline).foregroundStyle(.secondary).frame(minHeight: 44)
            }.accessibilityIdentifier("fleet.connection")
        }
    }
    @ViewBuilder private func sessionSection(_ title: String, symbol: String, sessions: [RelaySession], tint: Color) -> some View {
        if !sessions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Label(title, systemImage: symbol).foregroundStyle(tint)
                    Text("\(sessions.count)").foregroundStyle(.secondary).monospacedDigit()
                    Spacer()
                }.font(.subheadline.weight(.semibold)).padding(.horizontal, 2).accessibilityAddTraits(.isHeader)
                ForEach(sessions) { session in
                    FleetSessionRow(session: session)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }
    private var catalogueControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cronologia su Codex").font(.caption).foregroundStyle(.secondary)
            ForEach(relay.machines.values.filter { machine.isEmpty || $0.id == machine }.sorted { $0.name < $1.name }) { host in
                Button {
                    if relay.catalogue.completed.contains(host.id) { relay.catalogue.restart(machine: host.id) }
                    Task { await relay.loadCatalogue(machine: host.id) }
                } label: {
                    HStack {
                        Text((relay.catalogue.completed.contains(host.id) ? "Rileggi cronologia · " : "Carica altre sessioni · ") + host.name)
                        Spacer()
                        if relay.catalogueLoading.contains(host.id) { ProgressView() }
                    }.font(.subheadline).frame(minHeight: 44)
                }.disabled(!relay.online || host.status != "ONLINE" || relay.catalogueLoading.contains(host.id))
                    .accessibilityIdentifier("catalogue.load." + host.id)
                if let error = relay.catalogueErrors[host.id] { Text(error).font(.caption).foregroundStyle(RelayPalette.failure) }
            }
        }.padding(16).background(RelayPalette.surface, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct FleetSessionRow: View {
    @Environment(RelayController.self) private var relay
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let session: RelaySession
    private var status: String { session.displayStatus(machine: relay.machines[session.machineId], connected: relay.online) }
    private var active: Bool { ["WORKING", "NEEDS_YOU"].contains(status) }
    var body: some View {
        Button { relay.open(session.id) } label: {
            HStack(alignment: .top, spacing: 12) {
                if active {
                    RoundedRectangle(cornerRadius: 2).fill(RelayPalette.status(status)).frame(width: 2)
                }
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 6) {
                        Text(relay.machines[session.machineId]?.name ?? session.machineId).fontWeight(.semibold)
                        if !session.project.isEmpty { Text("/"); Text(session.project).lineLimit(1) }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                    }.font(.caption).foregroundStyle(.secondary)
                    Text(session.title).font(active ? .headline : .subheadline.weight(.medium)).lineLimit(2).foregroundStyle(.primary)
                    if status == "WORKING", let activity = relay.liveActivities[session.id] {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: activity.kind == "terminal" ? "terminal" : activity.kind == "tool" ? "wrench.and.screwdriver" : activity.kind == "file" || activity.kind == "diff" ? "doc.text" : "text.bubble")
                                .foregroundStyle(RelayPalette.working)
                            Text(activity.detail).lineLimit(2)
                        }.font(.caption).foregroundStyle(.secondary)
                            .contentTransition(.opacity)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: activity.itemId)
                    }
                    HStack(spacing: 6) {
                        SessionStatusMark(status: status)
                        Text(status == "OFFLINE" ? relay.machineConnectionLabel(session.machineId) : statusLabel(status))
                            .foregroundStyle(active ? RelayPalette.status(status) : .secondary)
                        Spacer(minLength: 4)
                        if status == "WORKING" { ElapsedLabel(start: session.turnStarted).monospacedDigit() }
                    }.font(.caption)
                    if ["OFFLINE", "SYNCING", "RECONNECTING", "DEGRADED"].contains(status) {
                        LastKnownSession(session: session, machine: relay.machines[session.machineId])
                    }
                }
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(RelayPalette.surface, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(active ? RelayPalette.status(status).opacity(0.2) : Color.primary.opacity(0.045)))
                .contentShape(RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(RelayRowPressStyle()).accessibilityIdentifier("session." + session.id)
    }
}

// Shared date handling accepts both Relay timestamp encodings.
enum RelayDate {
    static func parse(_ value: String?) -> Date? {
        guard let value, !value.hasPrefix("0001-") else { return nil }
        let parser = ISO8601DateFormatter()
        if let date = parser.date(from: value) { return date }
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return parser.date(from: value)
    }
}

private struct SearchChrome: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) { content.glassEffect(.regular, in: Capsule()) }
        else { content.background(.regularMaterial, in: Capsule()) }
    }
}
