# Native navigation

Each entity has one home. Other views show compact relationships or exceptions,
then navigate to that home; they do not embed another management inventory.

| Home | Responsibility |
| --- | --- |
| Fleet | Needs You, current work, bounded recent work; search and All Sessions |
| Needs You | Canonical pending RPC decisions and a distinct transient Live Questions section |
| Machines | Inventory, connection/runtime state, access management |
| Machine → Diagnostics | Heartbeat, epoch, sequence, snapshot and adapter measurements |
| Codex Accounts | Runtime identity, plan, dynamic windows and supported quota data |
| Controllers & Access | Authorized controllers, enrollment, revocation and local sign-out |
| Diagnostics | Hub/system health, aggregate state, transport timing, redacted copy |
| Settings | Hub configuration/access context, notification preferences and About |
| Session | One conversation, current heartbeat, composer and activity inspection |

## Navigation choice

The previous Fleet / Needs You / Settings three-tab model was compared visually
with two work tabs and a native Relay administration sheet on iPhone 16. The
latter is retained: Fleet and Needs You remain one-handed, persistent work routes;
less-frequent administration is one menu away. A sheet preserves spatial context
without introducing a custom drawer or presenting Settings as current work.
Administrative navigation disappears inside a session.

The Relay menu links to Machines, Accounts, All Sessions, Controllers, Diagnostics
and Settings. Settings does not repeat those administrative destinations. Account
“Used on” opens a filtered version of the canonical Machines view. Global
Diagnostics links to Machines, while per-machine measurements live in its detail.

## Quiet normal state

A healthy Fleet has no permanent connected/count banner. Connection exceptions
produce one actionable warning leading to Machines. A Working row has three
compact lines: machine/project, title, then operation category and elapsed time.
Terminal, Changes, Tools or Response shares the neutral activity sweep; full shell
bodies stay in the session. Completed activity does not masquerade as a running
operation. Healthy infrastructure is neutral. Needs You uses a
restrained warning treatment. Status labels accompany color.

Consecutive command/tool/file activity in the same turn shares one stable inline
group between conversational messages. Previews show the latest command/tool and
basename-first file links; a file opens directly in its diff. Terminal summaries
include a bounded live output line. Detailed executions, exit status and output
belong in Terminal.
The compact jump-to-latest button does not change reader-intent scroll rules:
streaming, keyboard changes and drag inertia never imply permission to force-scroll.

[Navigation](../assets/app/screenshots/navigation.png) ·
[Settings](../assets/app/screenshots/settings.png) ·
[Machine diagnostics](../assets/app/screenshots/machine-diagnostics.png)

The composer is one material surface with integrated 44-point controls. Session
Info belongs to the header; Steer/Interrupt remain in an anchored composer action
panel. The composer and keyboard remain visible when it opens. Copy Session Link
and duplicate send actions are absent; queued-message editing appears only when
supported. The panel clears when the current turn or connection changes. A compact
neutral Working text sweep respects Reduce Motion and does not animate transcript
updates. Context compaction replaces the Working label only while a real current
compaction item is running; the last command is not repeated below the heartbeat.
