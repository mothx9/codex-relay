import SwiftUI

/// Shared semantic roles; active Fleet rows use quiet glass, activity content is opaque.
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
            LazyVStack(alignment: .leading, spacing: 18) {
                if search.isEmpty { fleetHeader }
                if !browsingAll {
                    sessionSection(String(localized: "Needs You", bundle: relayLocalizationBundle), sessions: sorted.filter { state($0) == "NEEDS_YOU" }, tint: RelayPalette.attention)
                    sessionSection(String(localized: "Working", bundle: relayLocalizationBundle), sessions: sorted.filter { state($0) == "WORKING" }.sorted { ($0.turnStarted ?? "", $0.id) > ($1.turnStarted ?? "", $1.id) }, tint: .primary)
                    sessionSection(String(localized: "Recent", bundle: relayLocalizationBundle), sessions: Array(sorted.filter { !["WORKING", "NEEDS_YOU"].contains(state($0)) }.prefix(6)), tint: .secondary)
                    Button { filter = "HISTORY" } label: {
                        HStack {
                            Label(String(localized: "All sessions", bundle: relayLocalizationBundle), systemImage: "clock.arrow.circlepath")
                            Spacer()
                            Text("\(sorted.count)").monospacedDigit().foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        }.font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 12).padding(.horizontal, 4)
                    }.buttonStyle(RelayRowPressStyle()).accessibilityIdentifier("fleet.history")
                } else {
                    sessionSection(filter == "HISTORY" || filter == "ALL" ? String(localized: "Sessions", bundle: relayLocalizationBundle) : statusLabel(filter), sessions: visible, tint: .secondary)
                    if visible.isEmpty { ContentUnavailableView.search(text: search) }
                    if filter == "HISTORY" || !search.isEmpty { catalogueControls }
                }
            }.padding(.horizontal, RelaySpacing.page).padding(.top, 4).padding(.bottom, 16)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(String(localized: "Search", bundle: relayLocalizationBundle), text: $search)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("fleet.search")
                if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.accessibilityLabel(String(localized: "Clear search", bundle: relayLocalizationBundle)).frame(minWidth: 44, minHeight: 44) }
            }.padding(.horizontal, 16).frame(minHeight: 44).modifier(SearchChrome())
                .padding(.horizontal, RelaySpacing.page).padding(.vertical, 8)
        }
        .background(Color(uiColor: .systemBackground))
        .sheet(isPresented: $showingMachines) {
            NavigationStack {
                MachinesView().toolbar { ToolbarItem(placement: .confirmationAction) { Button(String(localized: "Close", bundle: relayLocalizationBundle)) { showingMachines = false }.accessibilityIdentifier("machines.close") } }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: sorted.filter { state($0) == "NEEDS_YOU" }.map(\.id).sorted())
    }

    @ViewBuilder private var fleetHeader: some View {
        let exceptions = relay.machines.values.filter { $0.status != "ONLINE" }
        if !relay.online || !exceptions.isEmpty {
            Button { showingMachines = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                    if !relay.online { Text(String(localized: "Connecting to Hub…", bundle: relayLocalizationBundle)) }
                    else if exceptions.count == 1, let host = exceptions.first { Text("\(host.name) · \(relay.machineConnectionLabel(host.id))") }
                    else { Text(String(localized: "\(exceptions.count) machines need attention", bundle: relayLocalizationBundle)) }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                }.font(.subheadline).foregroundStyle(RelayPalette.attention).frame(minHeight: 44)
            }.accessibilityIdentifier("fleet.connection")
        }
    }
    @ViewBuilder private func sessionSection(_ title: String, sessions: [RelaySession], tint: Color) -> some View {
        if !sessions.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title).foregroundStyle(tint)
                    Text("\(sessions.count)").foregroundStyle(.secondary).monospacedDigit()
                    Spacer()
                }.font(.footnote.weight(.semibold)).padding(.horizontal, 12).accessibilityAddTraits(.isHeader)
                VStack(spacing: sessions.contains(where: { ["WORKING", "NEEDS_YOU"].contains(state($0)) }) ? 6 : 0) {
                    ForEach(sessions) { session in
                        FleetSessionRow(session: session)
                    }
                }
            }
        }
    }
    private var catalogueControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "History on Codex", bundle: relayLocalizationBundle)).font(.caption).foregroundStyle(.secondary)
            ForEach(relay.machines.values.filter { machine.isEmpty || $0.id == machine }.sorted { $0.name < $1.name }) { host in
                Button {
                    if relay.catalogue.completed.contains(host.id) { relay.catalogue.restart(machine: host.id) }
                    Task { await relay.loadCatalogue(machine: host.id) }
                } label: {
                    HStack {
                        Text((relay.catalogue.completed.contains(host.id) ? String(localized: "Reload history · ", bundle: relayLocalizationBundle) : String(localized: "Load more sessions · ", bundle: relayLocalizationBundle)) + host.name)
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
    @Environment(\.dynamicTypeSize) private var typeSize
    let session: RelaySession
    private var status: String { session.displayStatus(machine: relay.machines[session.machineId], connected: relay.online) }
    private var active: Bool { ["WORKING", "NEEDS_YOU"].contains(status) }
    private var source: String { [relay.machines[session.machineId]?.name ?? session.machineId, session.project].filter { !$0.isEmpty }.joined(separator: " · ") }
    private var showsState: Bool { status != "READY" }
    private var lastKnown: Bool { ["OFFLINE", "SYNCING", "RECONNECTING", "DEGRADED"].contains(status) }
    var body: some View {
        Button { relay.open(session.id) } label: {
            VStack(alignment: .leading, spacing: 4) {
                if typeSize.isAccessibilitySize {
                    Text(session.title).font(.body.weight(active ? .medium : .regular)).foregroundStyle(status == "INACTIVE" ? .secondary : .primary)
                    Text(source).font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("session.source." + session.id)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(session.title).font(.body.weight(active ? .medium : .regular)).lineLimit(2)
                            .foregroundStyle(status == "INACTIVE" ? .secondary : .primary).frame(maxWidth: .infinity, alignment: .leading)
                        Text(source).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                            .layoutPriority(1)
                            .accessibilityIdentifier("session.source." + session.id)
                    }
                }
                if showsState { HStack(spacing: 6) {
                    if status == "WORKING" {
                        Circle().fill(RelayPalette.working).frame(width: 5, height: 5).accessibilityHidden(true)
                        WorkingText(text: statusLabel(status), highlight: RelayPalette.working, resting: RelayPalette.working.opacity(0.8)).fixedSize()
                        if let category = relay.liveActivities[session.id]?.fleetSummary, category != statusLabel(status) {
                            Text("·").foregroundStyle(.secondary)
                            Text(category).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        ElapsedLabel(start: session.turnStarted).monospacedDigit().foregroundStyle(.secondary)
                    } else {
                        SessionStatusMark(status: status)
                        Text(status == "OFFLINE" ? relay.machineConnectionLabel(session.machineId) : statusLabel(status))
                            .foregroundStyle(RelayPalette.status(status)).lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                        Spacer(minLength: 4)
                    }
                }.font(.footnote) }
                if lastKnown { LastKnownSession(session: session, machine: relay.machines[session.machineId]) }
            }.padding(.horizontal, 12).padding(.vertical, 10).frame(minHeight: 44)
                .frame(maxWidth: .infinity, alignment: .leading).contentShape(RoundedRectangle(cornerRadius: 12))
                .modifier(FleetRowSurface(emphasized: active))
        }.buttonStyle(RelayRowPressStyle()).accessibilityIdentifier("session." + session.id)
    }
}

private struct FleetRowSurface: ViewModifier {
    let emphasized: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if emphasized {
            if #available(iOS 26.0, *) { content.glassEffect(.clear, in: RoundedRectangle(cornerRadius: 14)) }
            else { content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14)) }
        } else { content }
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
