# M1 reliability validation

Validation date: 2026-10-07. Service build: `0.1.0-rc.4+m1.4`.
Installed Codex schema: `0.160.1`. Operational addresses, credentials, device
identifiers and private transcripts are intentionally excluded.

## Automated acceptance

- `make check`: formatting, `go vet ./...`, `go test -race ./...`, web tests and
  installer tests pass.
- `go test ./...`: pass.
- `swift test --package-path native`: 37 tests pass.
- iPhone 16 simulator build and build-for-testing pass.
- Signed physical iPhone build and installation pass.

| Required invariant | Regression coverage |
| --- | --- |
| Disconnect preserves Working as stale; reconnect first Syncing, then Online | `TestConnectionRequiresSnapshotAndRejectsOldEpoch`; Swift `testConnectionStatesPreserveLastKnownWork` |
| Old peer/epoch cannot mutate current state | `TestConnectionRequiresSnapshotAndRejectsOldEpoch`; Swift `testEpochSequenceAndSnapshotWatermark` |
| Duplicate/reordered events and older snapshots cannot regress state | `TestOrderingAndRestartRouting`, `TestSnapshotRevisionRejectsEqualWatermarkReplay` |
| Pending request outside catalogue creates a visible session and survives refresh/age | `TestPendingUnseenSessionSurvivesRefreshAndAge` |
| Hub restart retains pending routing without persisting sensitive payload | `TestOrderingAndRestartRouting` |
| Snapshot storage failure retains previous durable state | `TestSnapshotCommitFailureKeepsPreviousDurableState` |
| Codex unavailable preserves last-known state | `TestDegradedAnnouncePreservesLastKnownSession` |
| Agent reconstruction follows every loaded page; active/Needs You outrank history | `TestSnapshotPagedLoadedAndPendingOutsideCatalogue` |
| Replay preserves request identity and one-shot reservation | `TestPendingReplayKeepsIncarnationAndOneShotReservation` |
| Timing is bounded and contains no secrets | `TestDiagnosticsBoundedAndSecretFree` |
| Periodic refresh does not misreport uptime as reconnect duration | `TestPeriodicSnapshotDoesNotTurnSyncTimingIntoUptime` |
| Slow optional account reads cannot block state/event synchronization | `TestRefreshAndLiveSnapshotProceedWhileAccountReadBlocked` |
| Snapshot watermark cannot discard unseen transcript events | `TestRefreshDeliversTranscriptBeforeAdvancingSnapshotCursor` |
| Cold history pages do not subscribe or replace live state | `TestColdCataloguePagesDoNotReplaceLiveOrSubscribe`, `TestColdDiscoveryCannotGrantCanonicalState` |
| Native cold cache remains bounded and canonical pending state wins | `testCatalogueIsBoundedAndCannotReplaceCanonicalPending` |

Existing control/outbox tests continue to cover uncertain outcomes, no automatic
resend, canonical message identity, expected-turn steering, and one-shot answers.

## Real deployment acceptance

The existing Hub and three Agents were upgraded sequentially. Existing database,
credential and service configuration were preserved; shared Codex daemon process
identities were unchanged. The Hub restart rehydrated all three workers Online.

One owned validation thread was reused, then archived. A real supported
`request_user_input` was observed by the Hub and shown by native Fleet, Inbox and
inline conversation. It survived an Agent restart. The inline form remained
stable for ten seconds. Resolution from another client removed it everywhere;
application termination/relaunch did not restore it.

`testOwnedPendingRequestAcrossSurfacesAndResolveElsewhere` verifies this sequence.
`testLiveLastKnownWorkingAcrossAgentSilence` verifies silent Agent loss and
recovery while leaving Codex running. The final run detected Offline after about
72 seconds of Agent suspension, displayed last-known Working next to the disabled
composer, and restored current state after the Agent resumed. The assertion uses
`isHittable`, not merely off-screen element existence. Screenshot review caught
and corrected the earlier off-screen placement.

`testLiveCataloguePaginationIsReadOnly` fetched every catalogue page from all
three workers through the real Hub; `testLiveReadOnlySettingsSurfaces` also
passed. Screenshots were inspected for Fleet, inline request, Inbox, offline
conversation, catalogue controls and settings.

The physical iPhone connected successfully, confirmed by the owner. The final
build was subsequently installed and launched through Apple device tooling.

## Measurements and limits

Final initial snapshot / connection-to-Online observations were approximately:

| Worker platform | Snapshot | Connected to Online |
| --- | ---: | ---: |
| Linux x86-64 | 72 ms | 171 ms |
| Linux ARM64 | 307 ms | 350 ms |
| macOS ARM64 | 179 ms | 821 ms |

These are observations, not percentile guarantees. Earlier account reads on the
critical path produced approximately 559 ms and 1163 ms connection-to-Online on
the two Linux workers. They now run separately. A real pending-request sample
arrived at the Hub about 333 ms after Agent observation. Cross-host clock offset
is included; Codex model-emission time is not available.

The installation had 398 persisted catalogue threads and 13 loaded threads;
their union was 403 because some loaded threads had no persisted rollout. The
canonical operational set was 8 sessions; approximately 390 catalogue entries
were cold. Metadata-only enumeration took approximately 10–149 ms per worker.
The initial set stays bounded; additional history is now discovered in pages.

Observed steady RSS was about 21 MB for the Hub and 16–24 MB per Agent. This is
point-in-time process RSS, not a memory leak or long-duration load benchmark.
Three independent clock brackets proved the Hub clock ahead of the Mac by
at least approximately 59 ms. Therefore native one-way latency could not be
reported reliably in this run: the UI reports clock misalignment instead of
a zero/negative transport time. No clock or network configuration was changed.
Native diagnostics expose bounded Hub-receipt estimates and reducer application
time; neither is a SwiftUI frame-rendering measurement. VPN configuration was
not changed and transport latency was not attributed to a VPN without evidence.

## Scope boundaries

M1 establishes canonical reliability. The event audit records schema-supported
terminal interactions, granular MCP progress and file output/patch events that
are not yet separately normalized. Their UI presentation belongs to a subsequent
product milestone. APNs entitlement availability does not affect M1 acceptance.
