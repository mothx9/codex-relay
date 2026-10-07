# Codex account metadata

Relay observes the already-authenticated local Codex runtime. It does not offer
OpenAI login, scrape a website, refresh login tokens, or forward credentials.

The adapter allowlists account kind, email and plan from `account/read`. The
installed Codex 0.160.1 schema also exposes an optional account ID in
`account/rateLimits/read`, named/model-specific quota buckets, duration-labelled
usage windows and resets, credits, spend controls, included-usage permission and
reset-credit metadata. Only those typed fields are transported. Opaque upsell,
authentication and workspace-routing objects are excluded.

Sparse quota events update their bucket without erasing another bucket's windows.
An account-change event clears previous identity and quotas. A complete subsequent
read reconstructs the new account. Missing permission is unknown, not permission
to resume ordinary usage. Percentages and reset dates do not override it.

## Derived registry

Authenticated `GET /api/accounts` returns a derived view of accepted machine
reports. It is not another account database:

- Group by supported account ID when present.
- Otherwise group ChatGPT identities by normalized reported email, explicitly
  labelled as an email-based fallback.
- Keep anonymous/API-key runtimes machine-scoped; never infer that their keys match.
- Retain source machines and identify the selected report's source.
- Prefer a current source, then the latest **Hub receipt time**. Worker clock
  differences cannot choose the winning report.
- A report is current only on an Online machine, received during its current
  connection, and at most five minutes old. Older reports remain last-known.

Registry IDs are hashes of the grouping identity, not credentials. The endpoint
contains private account metadata and requires controller authentication; it must
not be published as diagnostics or included in public screenshots.

Thread token counters include input, cached/cache-write input, output, reasoning
output count and total, plus model context-window size when reported. These are
accounting numbers, never reasoning text. Cumulative totals are not current
context occupancy. Relay does not calculate bills or unsupported analytics.

## Presentation and units

Accounts own usage presentation; “Used on” links to the canonical machine list.
Duration-based windows show remaining capacity: `clamp(100 - usedPercent, 0, 100)`.
The progress bar represents that same remaining fraction. Labels derive from
reported duration, not primary/secondary bucket position. Relative update age is
primary. Source-machine provenance and identity fallback belong in expandable data details. Missing data is never represented as zero.

Codex 0.160.1's `CreditsSnapshot.balance` is an optional string alongside
`hasCredits` and `unlimited`; its protocol definition provides no currency,
unit or precision contract. Relay therefore shows availability/unlimited state
in the primary UI. The exact reported balance is inspectable in Data details
with an explicit unknown-unit explanation. Relay does not convert it into money
or infer a purchase value. Reset credits are a separate typed count.
