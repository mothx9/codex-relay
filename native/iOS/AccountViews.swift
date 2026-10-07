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
                            Text([entry.account.plan, "\(entry.machines.count) machines", entry.fresh && relay.online ? String(localized: "Current", bundle: relayLocalizationBundle) : String(localized: "Last known", bundle: relayLocalizationBundle)].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, RelaySpacing.small)
                    }.accessibilityIdentifier("account." + entry.id)
                }
                if relay.accounts.isEmpty {
                    ContentUnavailableView(String(localized: "No account data yet", bundle: relayLocalizationBundle), systemImage: "person.crop.circle", description: Text(String(localized: "Accounts are reported by Codex on your machines. Sign in to Codex locally to make account data available.", bundle: relayLocalizationBundle)))
                }
                if let error = relay.settingsErrors["accounts"] { Text(error).font(.caption).foregroundStyle(RelayPalette.failure) }
            } footer: { Text(String(localized: "Relay reads account metadata from your existing Codex runtime. OpenAI login credentials stay on each machine.", bundle: relayLocalizationBundle)) }
        }.navigationTitle(String(localized: "Codex Accounts", bundle: relayLocalizationBundle)).navigationBarTitleDisplayMode(.inline)
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
                    if let plan = entry.account.plan, !plan.isEmpty { LabeledContent(String(localized: "Plan", bundle: relayLocalizationBundle), value: plan.capitalized) }
                    LabeledContent(String(localized: "Data", bundle: relayLocalizationBundle), value: entry.fresh && relay.online ? String(localized: "Current", bundle: relayLocalizationBundle) : String(localized: "Last known", bundle: relayLocalizationBundle))
                    if let date = RelayDate.parse(entry.updatedAt) { LabeledContent(String(localized: "Updated", bundle: relayLocalizationBundle)) { Text(date, style: .relative) } }
                }
                ForEach(entry.account.usageBuckets, id: \.0) { key, bucket in
                    Section(bucket.limitName ?? key) {
                        if let model = bucket.normalModelSlug { LabeledContent(String(localized: "Model", bundle: relayLocalizationBundle), value: model) }
                        if let window = bucket.primary { UsageWindowView(window: window) }
                        if let window = bucket.secondary { UsageWindowView(window: window) }
                        if let credits = bucket.credits {
                            LabeledContent(String(localized: "Credits", bundle: relayLocalizationBundle), value: credits.unlimited ? String(localized: "Unlimited", bundle: relayLocalizationBundle) : credits.displayBalance ?? (credits.hasCredits ? String(localized: "Available", bundle: relayLocalizationBundle) : String(localized: "None available", bundle: relayLocalizationBundle)))
                        }
                        if let limit = bucket.individualLimit {
                            LabeledContent(String(localized: "Spend limit", bundle: relayLocalizationBundle), value: limit.limit)
                            LabeledContent(String(localized: "Used", bundle: relayLocalizationBundle), value: limit.used)
                            LabeledContent(String(localized: "Remaining", bundle: relayLocalizationBundle), value: "\(limit.remainingPercent)%")
                            LabeledContent(String(localized: "Resets", bundle: relayLocalizationBundle)) { Text(Date(timeIntervalSince1970: Double(limit.resetsAt)), style: .date) }
                        }
                        if let reached = bucket.spendControlReached { LabeledContent(String(localized: "Spend control", bundle: relayLocalizationBundle), value: reached ? String(localized: "Limit reached", bundle: relayLocalizationBundle) : String(localized: "Within limit", bundle: relayLocalizationBundle)) }
                        if let reached = bucket.rateLimitReachedType, !reached.isEmpty { LabeledContent(String(localized: "Limit state", bundle: relayLocalizationBundle), value: reached) }
                    }
                }
                if let allowed = entry.account.ordinaryUsageAllowed {
                    Section { LabeledContent(String(localized: "Included usage", bundle: relayLocalizationBundle), value: allowed ? String(localized: "Available", bundle: relayLocalizationBundle) : String(localized: "Not available", bundle: relayLocalizationBundle)) }
                }
                if let credits = entry.account.resetCredits {
                    Section(String(localized: "Reset credits", bundle: relayLocalizationBundle)) {
                        LabeledContent(String(localized: "Available", bundle: relayLocalizationBundle), value: "\(credits.availableCount)")
                        ForEach(credits.credits ?? []) { credit in
                            VStack(alignment: .leading, spacing: RelaySpacing.small) {
                                Text(credit.title ?? String(localized: "Reset credit", bundle: relayLocalizationBundle))
                                if let description = credit.description { Text(description).font(.caption).foregroundStyle(.secondary) }
                                if let expires = credit.expiresAt { Text("Expires \(Date(timeIntervalSince1970: Double(expires)), style: .date)").font(.caption) }
                            }
                        }
                    }
                }
                Section(String(localized: "Machines", bundle: relayLocalizationBundle)) {
                    ForEach(entry.machines, id: \.self) { machine in
                        NavigationLink { MachineSettingsView(id: machine) } label: {
                            LabeledContent(relay.machines[machine]?.name ?? machine, value: relay.machineConnectionLabel(machine))
                        }
                    }
                }
                Section {
                    LabeledContent(String(localized: "Reported by", bundle: relayLocalizationBundle), value: relay.machines[entry.sourceMachine]?.name ?? entry.sourceMachine)
                    if entry.identityBasis == "email" { Text(String(localized: "Grouped by the email Codex reports; an account identifier was unavailable.", bundle: relayLocalizationBundle)).font(.caption).foregroundStyle(.secondary) }
                    Text(String(localized: "Usage windows and balances are reported by Codex. Missing values are not estimated.", bundle: relayLocalizationBundle)).font(.caption).foregroundStyle(.secondary)
                }
            } else { ContentUnavailableView(String(localized: "Account no longer reported", bundle: relayLocalizationBundle), systemImage: "person.crop.circle.badge.questionmark") }
        }.navigationTitle(String(localized: "Codex Account", bundle: relayLocalizationBundle)).navigationBarTitleDisplayMode(.inline)
            .refreshable { await relay.loadAccounts() }
    }
}
private struct UsageWindowView: View {
    let window: RateWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text(window.label); Spacer(); Text(String(localized: "\(window.usedPercent)% used", bundle: relayLocalizationBundle)).monospacedDigit() }.font(.subheadline)
            ProgressView(value: window.fraction).tint(window.usedPercent >= 100 ? RelayPalette.attention : Color.accentColor)
                .accessibilityLabel(window.label).accessibilityValue(String(localized: "\(window.usedPercent)% used", bundle: relayLocalizationBundle))
            if let reset = window.resetsAt {
                Text("Resets \(Date(timeIntervalSince1970: Double(reset)), format: .dateTime.month(.abbreviated).day().hour().minute())").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, RelaySpacing.compact)
    }
}
struct SessionUsageView: View {
    let usage: TokenUsage
    var body: some View {
        Section(String(localized: "Token usage", bundle: relayLocalizationBundle)) {
            if let window = usage.modelContextWindow { LabeledContent(String(localized: "Model context window", bundle: relayLocalizationBundle), value: window.formatted()) }
            LabeledContent("Input", value: usage.total.inputTokens.formatted())
            LabeledContent(String(localized: "Cached input", bundle: relayLocalizationBundle), value: usage.total.cachedInputTokens.formatted())
            if let writes = usage.total.cacheWriteInputTokens { LabeledContent(String(localized: "Cache write input", bundle: relayLocalizationBundle), value: writes.formatted()) }
            LabeledContent("Output", value: usage.total.outputTokens.formatted())
            if let reasoning = usage.total.reasoningOutputTokens { LabeledContent(String(localized: "Reasoning output tokens", bundle: relayLocalizationBundle), value: reasoning.formatted()) }
            LabeledContent(String(localized: "Total", bundle: relayLocalizationBundle), value: usage.total.totalTokens.formatted())
            Text(String(localized: "Cumulative counters reported by Codex; totals are not a measure of current context occupancy.", bundle: relayLocalizationBundle)).font(.caption).foregroundStyle(.secondary)
        }
    }
}
