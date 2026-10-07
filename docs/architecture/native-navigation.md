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
produce one actionable warning leading to Machines. At ordinary text sizes a
Working row has two lines: title and machine/project, then activity category and
elapsed time. The state stays explicit as `● Working`, with a green sweep. The current activity
(Terminal, Changes, Tools, response generation or context compaction) follows in
secondary text, separated by a dot. Reduce Motion shows steady green. Full shell
bodies stay in the session; completed activity never masquerades as a running
operation. Needs You stays orange, failures red, and stale connectivity explicit.
Accessibility text sizes use a vertical layout so identity remains readable.

Working and Needs You use compact, subtle glass surfaces; Recent remains a flat
index on the system canvas. Inactive titles are attenuated. Source metadata uses
the 13-point footnote role, closer to 17-point titles, without a fixed-width
column or shrinking the type. Long titles may wrap once. Rows keep 44-point hit
targets with 10-point vertical padding and smaller section gaps. Working order follows turn-start identity rather than
every live timestamp update. Recent rows omit a repeated Ready label. Needs You
and the Relay menu use the same title-first open-list hierarchy. Glass belongs to active Fleet emphasis and controls. Activity groups inside the
conversation have quiet opaque cards that contain their own semantic children.

Consecutive command/tool/file activity in the same turn shares one stable inline
group between conversational messages. The header and its children use one icon
column and one text column; expansion replaces the collapsed preview. Groups over
five items explicitly label their bounded preview as Latest activities.

| Action | Destination |
| --- | --- |
| Group chevron | Expand/collapse recent compact activity rows in place |
| Command/tool row, collapsed or expanded | That operation and its available output |
| One file preview | That file's patch |
| Multiple file preview | Changed files list; each file opens its own patch |
| View all activities | Compact list for exactly that group; tap one row for detail |

The aggregate does not eagerly expand every output or patch. Tool rows include
the source/server alongside the tool name, so `js` is not presented without context.
No route merges operations across conversational messages or turn identities.

<img src="../assets/architecture/activity-inspection.svg" width="850" alt="An inline activity group has separate routes to operations, changed files and its full compact activity list">

The compact jump-to-latest button does not change reader-intent scroll rules:
streaming, keyboard changes and drag inertia never imply permission to force-scroll.

[Navigation](../assets/app/screenshots/navigation.png) ·
[Settings](../assets/app/screenshots/settings.png) ·
[Machine diagnostics](../assets/app/screenshots/machine-diagnostics.png)

The composer is one material surface with integrated 44-point controls. Session
Info belongs to the header. The `+` panel contains attachments only. During work,
Send queues the input in Next up; its direct Steer button moves the selected
canonical entry into the current turn, preserving its client identity. Escape on
a physical keyboard targets the first queued entry. Stop replaces the empty send
button; queue editing remains on each queued row. The composer and keyboard stay
visible when the attachment panel opens. The field remains editable while offline
or when control is unavailable; only sending is gated. A live-question answer is
prepared as an explicit current-turn reply, without a separate `+` mode switch. A compact
neutral Working text sweep respects Reduce Motion and does not animate transcript
updates. Context compaction replaces the Working label only while a real current
compaction item is running; the last command is not repeated below the heartbeat.

Short current live questions open at the medium sheet detent on a material surface,
with a drag handle and a large detent available. Long or multiple questions and
accessibility text sizes open large. There is still only one composer-side reply
home; selection prepares an answer without sending. Canonical pending RPCs keep
their separate authoritative lifecycle.

Typography uses iOS system text styles and Dynamic Type. Code blocks use the
13-point footnote monospaced role at the standard size, below 17-point body prose.
OpenAI Sans is described in the [official brand guidelines](https://openai.com/brand/),
but its download portal requires access. No private app font has been extracted
or bundled; the native system family remains explicit.
