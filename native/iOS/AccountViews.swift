import SwiftUI

struct AccountsView: View {
    @Environment(RelayController.self) private var relay
    var body: some View {
        List {
            Section {
                ForEach(relay.accounts) { entry in
                    NavigationLink { AccountDetailView(id: entry.id) } label: {
                        VStack(alignment: .leading, spacing: RelaySpacing.compact) {
                            Text(entry.account.email ?? entry.account.kind).font(.body.weight(.medium))
                            Text([entry.account.plan, "\(entry.machines.count) machines", entry.fresh && relay.online ? "Current" : "Last known"].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, RelaySpacing.small)
                    }.accessibilityIdentifier("account." + entry.id)
                }
                if relay.accounts.isEmpty {
                    ContentUnavailableView("No account data yet", systemImage: "person.crop.circle", description: Text("Accounts are reported by Codex on your machines. Sign in to Codex locally to make account data available."))
                }
                if let error = relay.settingsErrors["accounts"] { Text(error).font(.caption).foregroundStyle(RelayPalette.failure) }
            } footer: { Text("Relay reads account metadata from your existing Codex runtime. OpenAI login credentials stay on each machine.") }
        }.navigationTitle("Codex Accounts").navigationBarTitleDisplayMode(.inline)
            .task { await relay.loadAccounts() }.refreshable { await relay.loadAccounts() }
            .onChange(of: relay.machines.mapValues { $0.account?.observedAt }) { _, _ in Task { await relay.loadAccounts() } }
    }
}
struct AccountDetailView: View {
    @Environment(RelayController.self) private var relay
    let id: String
    private var entry: AccountEntry? { relay.accounts.first { $0.id == id } }
    var body: some View {
        List {
            if let entry {
                Section {
                    Text(entry.account.email ?? entry.account.kind).font(.title3.weight(.semibold)).textSelection(.enabled)
                    if let plan = entry.account.plan, !plan.isEmpty { LabeledContent("Plan", value: plan.capitalized) }
                    LabeledContent("Data", value: entry.fresh && relay.online ? "Current" : "Last known")
                    if let date = RelayDate.parse(entry.updatedAt) { LabeledContent("Updated") { Text(date, style: .relative) } }
                }
                ForEach(entry.account.usageBuckets, id: \.0) { key, bucket in
                    Section(bucket.limitName ?? key) {
                        if let model = bucket.normalModelSlug { LabeledContent("Model", value: model) }
                        if let window = bucket.primary { UsageWindowView(window: window) }
                        if let window = bucket.secondary { UsageWindowView(window: window) }
                        if let credits = bucket.credits {
                            LabeledContent("Credits", value: credits.unlimited ? "Unlimited" : credits.balance ?? (credits.hasCredits ? "Available" : "None available"))
                        }
                        if let limit = bucket.individualLimit {
                            LabeledContent("Spend limit", value: limit.limit)
                            LabeledContent("Used", value: limit.used)
                            LabeledContent("Remaining", value: "\(limit.remainingPercent)%")
                            LabeledContent("Resets") { Text(Date(timeIntervalSince1970: Double(limit.resetsAt)), style: .date) }
                        }
                        if let reached = bucket.spendControlReached { LabeledContent("Spend control", value: reached ? "Limit reached" : "Within limit") }
                        if let reached = bucket.rateLimitReachedType, !reached.isEmpty { LabeledContent("Limit state", value: reached) }
                    }
                }
                if let allowed = entry.account.ordinaryUsageAllowed {
                    Section { LabeledContent("Included usage", value: allowed ? "Available" : "Not available") }
                }
                if let credits = entry.account.resetCredits {
                    Section("Reset credits") {
                        LabeledContent("Available", value: "\(credits.availableCount)")
                        ForEach(credits.credits ?? []) { credit in
                            VStack(alignment: .leading, spacing: RelaySpacing.small) {
                                Text(credit.title ?? "Reset credit")
                                if let description = credit.description { Text(description).font(.caption).foregroundStyle(.secondary) }
                                if let expires = credit.expiresAt { Text("Expires \(Date(timeIntervalSince1970: Double(expires)), style: .date)").font(.caption) }
                            }
                        }
                    }
                }
                Section("Machines") {
                    ForEach(entry.machines, id: \.self) { machine in
                        NavigationLink { MachineSettingsView(id: machine) } label: {
                            LabeledContent(relay.machines[machine]?.name ?? machine, value: relay.machineConnectionLabel(machine))
                        }
                    }
                }
                Section {
                    LabeledContent("Reported by", value: relay.machines[entry.sourceMachine]?.name ?? entry.sourceMachine)
                    if entry.identityBasis == "email" { Text("Grouped by the email Codex reports; an account identifier was unavailable.").font(.caption).foregroundStyle(.secondary) }
                    Text("Usage windows and balances are reported by Codex. Missing values are not estimated.").font(.caption).foregroundStyle(.secondary)
                }
            } else { ContentUnavailableView("Account no longer reported", systemImage: "person.crop.circle.badge.questionmark") }
        }.navigationTitle("Codex Account").navigationBarTitleDisplayMode(.inline)
            .refreshable { await relay.loadAccounts() }
    }
}
private struct UsageWindowView: View {
    let window: RateWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text(window.label); Spacer(); Text("\(window.usedPercent)% used").monospacedDigit() }.font(.subheadline)
            ProgressView(value: window.fraction).tint(window.usedPercent >= 100 ? RelayPalette.attention : RelayPalette.working)
                .accessibilityLabel(window.label).accessibilityValue("\(window.usedPercent)% used")
            if let reset = window.resetsAt {
                Text("Resets \(Date(timeIntervalSince1970: Double(reset)), format: .dateTime.month(.abbreviated).day().hour().minute())").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, RelaySpacing.compact)
    }
}
struct SessionUsageView: View {
    let usage: TokenUsage
    var body: some View {
        Section("Token usage") {
            if let window = usage.modelContextWindow { LabeledContent("Model context window", value: window.formatted()) }
            LabeledContent("Input", value: usage.total.inputTokens.formatted())
            LabeledContent("Cached input", value: usage.total.cachedInputTokens.formatted())
            if let writes = usage.total.cacheWriteInputTokens { LabeledContent("Cache write input", value: writes.formatted()) }
            LabeledContent("Output", value: usage.total.outputTokens.formatted())
            if let reasoning = usage.total.reasoningOutputTokens { LabeledContent("Reasoning output tokens", value: reasoning.formatted()) }
            LabeledContent("Total", value: usage.total.totalTokens.formatted())
            Text("Cumulative counters reported by Codex; totals are not a measure of current context occupancy.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
