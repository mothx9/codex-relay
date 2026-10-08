#!/usr/bin/env python3
"""Generate dependency-free, editable SVG architecture diagrams."""
from html import escape
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / 'docs/assets/architecture'
ROOT.mkdir(parents=True, exist_ok=True)

class Diagram:
    def __init__(self, title, subtitle, height=620):
        self.parts = [f'''<svg xmlns="http://www.w3.org/2000/svg" width="1000" height="{height}" viewBox="0 0 1000 {height}">
<title>{escape(title)}</title><desc>{escape(subtitle)}</desc>
<defs><marker id="arrow" markerWidth="10" markerHeight="10" refX="8" refY="5" orient="auto"><path d="M 0 1 L 8 5 L 0 9" fill="none" stroke="#8394aa" stroke-width="1.5"/></marker></defs>
<style>
.ink {{ fill: #20252c; }} .muted {{ fill: #566273; }} .panel {{ fill: #f3f5f7; }}
@media (prefers-color-scheme: dark) {{ .ink {{ fill: #f0f2f3; }} .muted {{ fill: #afb5bf; }} .panel {{ fill: #222830; }} }}
</style>
<g font-family="-apple-system,BlinkMacSystemFont,Segoe UI,Arial,sans-serif">
<text x="40" y="50" class="ink" font-size="26" font-weight="700">{escape(title)}</text>
<text x="40" y="81" class="muted" font-size="15">{escape(subtitle)}</text>''']
    def box(self,x,y,w,title,lines,accent='#8394aa'):
        h=60+len(lines)*22
        self.parts.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="14" class="panel" stroke="{accent}" stroke-width="1.5"/>')
        self.parts.append(f'<text x="{x+18}" y="{y+30}" class="ink" font-size="18" font-weight="600">{escape(title)}</text>')
        for i,line in enumerate(lines):
            self.parts.append(f'<text x="{x+18}" y="{y+58+i*22}" class="muted" font-size="14">{escape(line)}</text>')
    def arrow(self,coords,label='',lx=None,ly=None):
        self.parts.append(f'<path d="{coords}" fill="none" stroke="#8394aa" stroke-width="2" marker-end="url(#arrow)"/>')
        if label:self.parts.append(f'<text x="{lx}" y="{ly}" class="muted" font-size="14" text-anchor="middle">{escape(label)}</text>')
    def note(self,x,y,text):self.parts.append(f'<text x="{x}" y="{y}" class="muted" font-size="14">{escape(text)}</text>')
    def save(self,name):(ROOT/f'{name}.svg').write_text('\n'.join(self.parts)+ '\n</g></svg>\n')

d=Diagram('One Hub. Your Codex fleet.','The iPhone controls Relay. Codex remains the source of truth.',760)
d.box(360,112,280,'iPhone controller',['Live work · decisions · conversation'])
d.arrow('M 500 194 V 257','HTTPS / WSS',620,231)
d.box(340,268,320,'Relay Hub',['Fleet state · routing · controllers','SQLite metadata · notifications'])
for x,title in [(40,'Machine 1'),(365,'Machine 2'),(690,'Machine N')]:
 d.box(x,460,270,title,['Relay Agent','Local Codex shared daemon'])
 d.arrow(f'M {x+135} 460 V 410 H 500 V 372')
 d.note(x+16,596,'Codex login and execution stay local')
d.note(330,437,'Agents establish outbound WSS connections')
d.note(40,678,'No remote Codex listener · No Relay transcript database · No Relay cloud account')
d.save('architecture')
d=Diagram('Connection lifecycle','A connected transport is not proof of current Codex state.',500)
for x,title,lines,accent in [(40,'Offline',['Last-known state','Controls unavailable'],'#8394aa'),(365,'Syncing',['Fetch current snapshot','Replay pending requests'],'#e3a552'),(690,'Online',['Snapshot accepted','Current capabilities'],'#60b58a')]:d.box(x,155,270,title,lines,accent)
d.arrow('M 310 204 H 357','connect',334,185);d.arrow('M 635 204 H 682','admit',659,185)
d.box(365,340,270,'Degraded',['Agent reachable; Codex unavailable'],'#e3a552')
d.arrow('M 500 259 V 332','sync fails',574,326)
d.arrow('M 825 259 V 302 H 175 V 266','transport lost',230,290)
d.note(42,455,'Old epoch / stale watermark / reordered event: rejected, never a state regression')
d.save('connection-lifecycle')
d=Diagram('Needs You: one canonical request','Visibility does not depend on an open conversation.',620)
d.box(40,140,260,'Codex request',['Supported unresolved request'])
d.box(370,140,260,'Agent',['Observe · normalize · replay'])
d.box(700,140,260,'Hub request store',['One identity and incarnation'])
d.arrow('M 300 181 H 362');d.arrow('M 630 181 H 692')
for x,title in [(40,'Fleet + Inbox'),(370,'Inline conversation'),(700,'Notification routing')]:
 d.box(x,340,260,title,['Derived from the same request'])
 d.arrow(f'M 830 222 V 286 H {x+130} V 332')
d.note(40,495,'Answer is one-shot and currentness-gated. A push tap never grants approval.')
d.note(40,525,'Codex resolution elsewhere removes the request from every surface.')
d.note(40,555,'History pagination and controller disconnect cannot dismiss pending work.')
d.save('needs-you-flow')
d=Diagram('Follow-up lifecycle','Send queues future work. Tap Steer / Escape for selected current-turn input.',640)
for x,title,lines in [(40,'Sending',['Separate Next up area']), (365,'Queued',['Canonical order · direct Steer']), (690,'Dispatched',['Canonical turn starts'])]:d.box(x,145,270,title,lines)
d.arrow('M 310 186 H 357');d.arrow('M 635 186 H 682')
d.box(40,340,270,'Steer now',['Selected original input + identity','Acknowledged removal before Steer'])
d.box(690,340,270,'Canonical',['Reconcile by client identity','No duplicate user bubble'])
d.arrow('M 500 227 V 282 H 175 V 332')
d.arrow('M 310 381 H 682','same client identity',500,362)
d.arrow('M 825 227 V 332')
d.note(40,496,'ACK ≠ completion. Deterministic failure retains text for deliberate retry.')
d.note(40,526,'UNKNOWN_OUTCOME: inspect canonical state; never automatically resend.')
d.save('follow-up-flow')
d=Diagram('Trust boundaries','Self-hosted authority; runtime authentication stays on the worker.',650)
d.box(40,145,280,'Controller boundary',['iPhone Keychain credential','One-time pairing · revocable access'])
d.box(360,145,280,'Hub boundary',['Controller / machine token hashes','Routing and metadata only'])
d.box(680,145,280,'Worker boundary',['Distinct Agent credential','Local authenticated Codex runtime'])
d.arrow('M 320 202 H 352');d.arrow('M 680 202 H 648')
d.box(360,375,280,'Apple APNs / Web Push',['Hub-owned provider configuration','No message content · privacy controls'])
d.arrow('M 500 249 V 367')
d.note(40,550,'OpenAI login tokens never cross the worker boundary.')
d.note(40,580,'HTTPS/WSS and exact-origin browser checks. Notifications navigate; state authorizes.')
d.save('trust-boundaries')

d=Diagram('Two notification paths','Permission is separate from delivery readiness.',650)
d.box(40,145,420,'Connected local alerts',['Native controller observes a live event','Semantic dedupe + currentness guard','Banner + Notification Center / Lock Screen'])
d.box(540,145,420,'Remote APNs push',['Hub observes a live event','Apple entitlement + provider key + registration','APNs delivers while app is not connected'])
d.arrow('M 250 271 V 340 H 500 V 370');d.arrow('M 750 271 V 340 H 500 V 370')
d.box(300,380,400,'Safe navigation',['Tap waits for authentication and current state','Never approves from a payload'])
d.note(40,550,'Private content omitted. Active-session completion is quiet. No per-token notices.')
d.note(40,580,'Local alerts are best effort while connected; they do not replace APNs.')
d.save('notification-delivery')
d=Diagram('Live questions are observations','Distinct from canonical pending RPCs. Never reconstructed from history.',650)
d.box(40,145,260,'Codex live item',['Real turn and item identity','Visible questions and options'])
d.box(370,145,260,'Hub attention',['Current epoch and sequence','Fanout without transcript watch'])
d.box(700,145,260,'Native controller',['Inbox + composer reply access','One local or remote notice'])
d.arrow('M 300 186 H 362');d.arrow('M 630 186 H 692')
d.box(250,370,500,'Retire the hint',['Turn boundary / input / submission / disconnect','No authoritative pending-store mutation'])
d.arrow('M 830 249 V 317 H 500 V 362')
d.note(40,550,'History remains readable. Reconnect cannot prove currentness and does not replay hints.')
d.note(40,580,'Reply prepares a current-turn Steer draft. Review and send explicitly.')
d.save('live-question-flow')

d=Diagram('Images follow the same control path','Bounded ephemeral input; no Relay image database.',560)
d.box(40,155,270,'iPhone',['System photo picker / image drop','Downscale and strip metadata','Up to 2 images · 256 KiB each'])
d.box(365,155,270,'Canonical Hub',['Authorize controller + capability','Validate size, type and dimensions','Route without persistence'])
d.box(690,155,270,'Agent + Codex',['Map to official image input','Preserve turn/client identity','New Turn / Follow-up / Steer'])
d.arrow('M 310 230 H 357');d.arrow('M 635 230 H 682')
d.note(40,390,'Only JPEG/PNG bytes cross Relay. No URL fetch, remote file path, audio or video.')
d.note(40,420,'Codex owns history. Relay history carries attachment counts, not image payloads.')
d.note(40,450,'Unknown outcome retains the local draft. No automatic retry or resubmission.')
d.save('image-input')

# Distinct routes from one inline group; no full-output aggregate by default.
d=Diagram('Activity inspection','One group. Consistent rows. A specific destination for each tap.',640)
d.box(350,125,300,'Inline group',['Counts · state · recent rows'])
d.box(40,340,270,'Command / tool',['One operation','Available output · copy actions'])
d.box(365,340,270,'Changed files',["Only this group's files",'Choose one file → its patch'])
d.box(690,340,270,'All activities',['Compact list for this group','Choose one operation → detail'])
d.arrow('M 500 229 V 280 H 175 V 332','operation row',230,265)
d.arrow('M 500 229 V 332','file preview',565,298)
d.arrow('M 500 229 V 280 H 825 V 332','View all',765,265)
d.note(40,545,'Expansion replaces the collapsed preview. Outputs and patches open on demand.')
d.note(40,575,'Group identity follows the first operation; messages and turn boundaries remain intact.')
d.save('activity-inspection')
