# Native navigation

Each entity has one home. Other views show compact relationships or exceptions,
then navigate to that home; they do not embed another management inventory.

| Home | Responsibility |
| --- | --- |
| Fleet | Needs You, current work, bounded recent work; search and All Sessions |
| Needs You | Authoritative supported pending RPC decisions |
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
produce one actionable warning leading to Machines. Current work retains its
semantic green indicator; healthy infrastructure is neutral. Needs You uses a
restrained warning treatment. Status labels accompany color.

Terminal conversation cards summarize counts, current/last command and a bounded
live output line. Detailed executions, exit status and output belong in Terminal.
The compact jump-to-latest button does not change reader-intent scroll rules:
streaming, keyboard changes and drag inertia never imply permission to force-scroll.

[Navigation](../assets/app/screenshots/navigation.png) ·
[Settings](../assets/app/screenshots/settings.png) ·
[Machine diagnostics](../assets/app/screenshots/machine-diagnostics.png)
