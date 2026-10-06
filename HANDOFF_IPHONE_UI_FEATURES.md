# Handoff: upgrade nativo iPhone, UI e feature

Checkpoint: 6 ottobre 2026. Repository esistente: https://github.com/mothx9/codex-relay, branch `main`. Base funzionale della review: `1f4cf72`. Non ricreare il progetto.

## Richiesta attuale del proprietario

L'app è stata firmata, installata, aperta e abbinata sul vero iPhone. Il proprietario considera l'interfaccia attuale provvisoria e chiede un'interfaccia pensata davvero per iPhone, insieme a un upgrade delle feature. La prossima wave deve progettare e implementare questo upgrade, preservando il sistema già collegato e distinguendo le funzioni presenti dalle acceptance ancora mancanti.

Il controllo finale vede tutti e tre gli host ONLINE. Spark è tornato raggiungibile, ma il suo agent è ancora rc.3; APNs reale non è configurato. Il collegamento dell'iPhone non significa che ogni flusso nativo sia già verificato.

## Stato verificato

| Area | Stato concreto |
| --- | --- |
| Hub | L'unico Hub Zima esistente è stato aggiornato in place a rc.4. Stesso servizio e directory dati; DB, bootstrap, credenziali e VAPID preservati. |
| Rollback | Backup privato di binario, unità e SQLite. Un primo controllo di recovery fallito ha realmente ripristinato rc.3; il successivo upgrade rc.4 è riuscito. |
| Exon | Agent rc.4 aggiornato separatamente, con snapshot e account metadata. Codex non è stato riavviato. |
| MacBook | Agent rc.4 aggiornato separatamente attraverso il launchd esistente; credenziali e plist preservati. |
| Spark | Era offline durante l'upgrade. Nel controllo finale è ONLINE sul Hub e raggiungibile via SSH: servizio agent attivo, binario rc.3 linux/arm64. Enrollment preservato; upgrade rc.4, account metadata e nuova recovery restano aperti. |
| Controlli PWA precedenti | New Turn, Follow-up con riconciliazione esatta, Answer e recovery agent/Hub erano passati su tutti e tre gli host attraverso questo stesso Hub. Steer e Interrupt erano passati su Exon. Sono prove storiche della base, non acceptance del nuovo client nativo. |
| OTP sul Hub reale | Otto cifre, exchange riuscito, riuso rifiutato, scadenza reale dopo cinque minuti. Nessun token amministratore sul telefono. |
| Revoca e dispositivi | Su enrollment usa-e-getta: revoca operatore chiude WSS e produce HTTP 401; rimozione client; aggiunta agent, conflitto, pausa/ripresa, revoca, re-enrollment e rimozione. Nessun enrollment reale revocato per le prove. |
| App fisica | Personal Team del proprietario, Developer Mode confermata dopo il riavvio, profilo rigenerato per l'iPhone collegato, firma verificata, installazione e avvio riusciti. Il proprietario ha confermato pairing e apertura. |
| Ultime correzioni sull'iPhone | La build con le correzioni finali di controlli/reconnect è stata nuovamente firmata, installata e avviata con successo. |
| Native E2E nel simulatore | Hub HTTPS reale: pairing, Fleet dei tre host registrati, Keychain dopo riavvio del processo, New Turn sul thread isolato, risposta Codex fresca, un solo messaggio utente canonico, nessun duplicato ottimistico, foreground reconnect. Suite ripassata dopo le ultime correzioni. |
| Form native | Domande strutturate e approval comando/file; aggiunte review completa dei permessi e form MCP con campi tipizzati/schema/JSON. La live acceptance di queste form è ancora aperta. |
| Preview | Sei preview SwiftUI isolate: pairing, Fleet, Ready, Follow-up accodato, Needs You e dispositivi. Canvas Xcode verificato; nessun accesso a Keychain/Hub/notifiche dalle fixture. |
| APNs | Backend e client presenti; installer persistente completato e testato. Mancano team push-capable e chiavi del proprietario. Il Personal Team attuale non ha entitlement APNs. Nessuna prova di ricezione/tap reale. |
| Release | Rimane rc.4 nel codice/build distribuita privatamente. Nessun tag/release rc.4 e nessuna v0.1 finale pubblicati. L'installer scarica ancora la release pubblicata rc.3 se non si passa `--binary`. |

### Commit di questa continuazione

| Commit | Cambiamento |
| --- | --- |
| `4bb7ce4` | Preview isolate e protezione delle credenziali durante le preview. |
| `0bad44e` | La snapshot periodica dell'agent conserva la versione del protocollo; corretto il reconnect ricorrente provocato dalla versione mancante. Test WebSocket su snapshot successive della stessa connessione. |
| `20bd2ab` | Form permissions/MCP, JSON con chiavi arbitrarie preservate, validazione e test; team Apple spostato nella configurazione locale ignorata. |
| `d31b9ef` | Target XCUITest live, entitlement Keychain del simulatore e aggiornamento delle evidenze di deployment/installazione. |
| `aa9e573` | `--apns-config FILE|none` persistente nell'installer Hub, migrazione esplicita delle unità manuali, quattro test isolati e CI. |
| `1f4cf72` | Retry dei guasti temporanei del Hub, ritorno al pairing su 401/403, expected turn conservato nel retry Steer e nell'Interrupt prima della conferma. |

## Review dell'app attuale

Questa è una review del codice e delle prove disponibili, non una certificazione visiva completa del vero iPhone. Il proprietario ha già espresso chiaramente che la UI va rifatta. I flussi non ancora provati fisicamente restano aperti anche quando il backend/PWA ha prove storiche positive.

| Priorità | Riscontro e conseguenza | Intervento richiesto |
| --- | --- | --- |
| Alta | [SessionView](native/iOS/Views.swift) mette composer e azioni sotto tutta la cronologia nello stesso ScrollView. Non ci sono scroll-to-latest, gestione dei nuovi messaggi o composer ancorato al bordo. | Composer nativo sempre raggiungibile, safe area/tastiera, scroll iniziale e streaming controllati, pulsante per tornare ai messaggi recenti. Non trascinare l'utente in fondo mentre legge la cronologia. |
| Alta | Chat, output comandi, diff e metadata sono resi come testi prevalentemente monospaziati con etichette tecniche. Mancano gerarchia conversazionale, separazione degli eventi e presentazione dei contenuti. | Messaggi nativi leggibili, typography di sistema, codice/diff/output separati e collassabili, metadata secondari. Preservare selezione/copia e identità canoniche. |
| Alta | La Fleet è una lista piatta con filtri orizzontali e ricerca. Il nativo non implementa il grouping descritto per la PWA e non ha una inbox autonoma delle richieste. | Navigazione progettata per iPhone: Fleet, attenzione/Needs You e impostazioni/dispositivi; priorità alle richieste actionable, distinzione immediata fra host offline e stato del turno. |
| Alta | [logout](native/iOS/RelayController.swift) ignora il fallimento della richiesta server e dimentica comunque la credenziale locale. La UI promette «Esci e revoca» anche senza conferma di revoca. | Distinguere uscita locale e revoca confermata; non dichiarare revoca riuscita quando il Hub è irraggiungibile. Recovery esplicita e test del caso offline. |
| Media | `busy` copre soprattutto pairing; varie mutazioni dispositivi non hanno loading/disabled/error contestuali. I codici mostrano «valido 5 minuti» statico, senza usare la scadenza per lo stato della UI. | Stato per operazione, prevenzione dei doppi tap, esito leggibile, countdown/scadenza reale e generazione di un nuovo codice. |
| Media | [DevicesView](native/iOS/Views.swift) permette pausa/ripresa e rimozione macchina, e revoca operatore. Non espone revoca macchina separata o rimozione operatore, benché il backend le supporti. | Completare i flussi API esistenti con distinzione fra sospensione, revoca e rimozione; conferme contestuali e stato di questo iPhone. Codex deve continuare localmente. |
| Media | Le form permissions/MCP sono funzionali ma la review è ancora testo JSON e i form complessi richiedono editor JSON. | Form native più chiare, riepilogo di host/progetto/operazione/scope, evidenza dei campi obbligatori, errori locali e fallback locale esplicito per gli schemi non supportati. |
| Media | [MCPResponse](native/RelayCore/Models.swift) è un validatore custom di un sottoinsieme JSON Schema; usa numeri Double e non copre ogni keyword. | Fixture del protocollo effettivo, controllo delle keyword non supportate e della precisione numerica. Non presentarlo come validatore JSON Schema universale. Validare anche l'interazione live. |
| Media | Il tema è forzato scuro, varie superfici usano il bianco fisso e molte label sono tecniche o mescolano lingue. | Tema/adattamento di sistema, contrasto, Dynamic Type, VoiceOver, touch target, stati di focus, testo coerente e comprensibile. Verificare telefono piccolo, orientamento e tastiera. |
| Media | [Notifications.swift](native/iOS/Notifications.swift) inoltra il tap a un callback opzionale senza un buffer esplicito; il controller apre l'ID anche prima di avere la snapshot. | Verificare cold start, autenticazione mancante, sessione assente e sheet già aperta. Routing centralizzato, destinazione valida e stato di caricamento, senza perdita del tap. Il rischio viene dalla lettura del codice; il bug non è ancora riprodotto su APNs reale. |
| Media | Stato notifiche e token sono in parte RAM; non viene ricostruito interamente lo stato del consenso/registrazione a ogni avvio. | Leggere lo stato iOS, separare consenso da configurazione Hub e registrazione del device, gestire rinnovo token/riavvio e rendere visibile lo stato effettivo. |
| Media | View, fixture e flussi sono concentrati in [Views.swift](native/iOS/Views.swift); routing, transport e mutazioni condividono un controller unico. | Separare schermate/componenti e modelli di presentazione quanto serve al redesign, senza creare un framework o un nuovo orchestratore. Conservare RelayCore e i contratti esistenti. |

Il link account apre ChatGPT e spiega di usare le impostazioni di sicurezza. Non esiste qui un'integrazione capace di gestire tutti i dispositivi/account ChatGPT: non trasformare quel link in una promessa di API che il sistema non ha.

## Piano della prossima wave

### 1. Prodotto e struttura nativa

Progettare una navigazione coerente per Fleet, richieste e impostazioni; trasformare il dettaglio sessione in una vera interazione da iPhone. Definire componenti, colori semantici, typography, spaziatura, tastiera, focus e feedback prima di aggiungere controlli sparsi. Il redesign generale della UI nativa è ora richiesto esplicitamente dal proprietario.

Ampliare le preview con stati vuoti, caricamento, reconnect, offline, read-only, errore invio, richiesta scaduta, permissions e MCP. Tutte le preview restano isolate dal vero Hub. Portare gli incrementi sul vero iPhone, non fermarsi al Canvas.

### 2. Flussi e feature già sostenuti dal backend

- Chat/composer adattivi: Ready avvia un turno; Working accoda un Follow-up; Needs You mostra la richiesta da risolvere.
- Mostrare subito il messaggio in invio, poi la fase accodata/dispatched; rimuovere il bubble ottimistico soltanto alla correlazione canonica esatta.
- Steer esplicito e Interrupt separato; draft conservato su errore, TURN_CHANGED leggibile e alternative soltanto su scelta esplicita.
- Inbox delle richieste con contesto chiaro, domande strutturate, approval comando/file, permissions per il solo turno e MCP nei limiti del protocollo.
- Completare aggiunta, pausa, ripresa, revoca e rimozione dei dispositivi. Usare enrollment usa-e-getta per le prove destructive.
- Rendere chiari macchina offline, accesso revocato, errore temporaneo, stato del Codex locale e account metadata disponibili.

Nuove feature come creazione/rinomina/archiviazione di thread o selezione di progetto vanno progettate e verificate contro l'app-server ufficiale prima di aggiungere nuovi comandi Relay. Non sono implementate né automaticamente incluse nei PASS attuali. Non assumere API account-wide o inventare un runtime alternativo.

### 3. Acceptance ancora aperte

| Prova | Simulatore nativo | Vero iPhone |
| --- | --- | --- |
| Pairing/Fleet | PASS; il test enumera gli host registrati. Il controllo finale separato vede tre host ONLINE | Confermati dal proprietario |
| Keychain dopo restart | PASS | Da automatizzare/verificare esplicitamente |
| New Turn + risposta canonica | PASS su thread isolato | Aperta |
| Follow-up immediato, accodato, eseguito una volta, senza duplicati | Aperta | Aperta |
| Answer live, richiesta risolta da altro client | Aperta | Aperta |
| Permissions/MCP live | Aperta; core/contratti non sono E2E | Aperta |
| Steer, stale TURN_CHANGED, Interrupt | Aperta; intent retention corretta e testata nel core | Aperta |
| Foreground reconnect | PASS | Aperta |
| UNKNOWN_OUTCOME senza resend automatico | Core/contratto presenti; E2E da completare | Aperta |
| Recovery app/agent/Hub con il nuovo nativo | Parziale; prove storiche PWA non trasferibili | Aperta |
| Sleep/wake e roaming | Richiedono collaborazione fisica del proprietario | Aperta |
| APNs con app chiusa e tap corretto, anche cold start | Il simulatore/fake provider non basta | Bloccata su team/capability/chiavi del proprietario |

Usare soltanto i thread di validation isolati indicati nell'handoff operativo privato. Non inviare comandi ai thread di lavoro ordinari. Non riavviare i daemon Codex condivisi per comodità.

### 4. Spark e APNs

Spark è ora raggiungibile: la prossima wave deve ricontrollarne lo stato e aggiornare soltanto l'agent Relay da rc.3 a rc.4 con backup/rollback, conservando il token. Confermare di nuovo le tre macchine e i metadata account. Non occorre chiedere al proprietario di riaccenderlo sulla base del vecchio checkpoint; nessuna modifica di rete e nessun restart del daemon Codex condiviso.

Per APNs servono un team Apple push-capable, provisioning coerente e la chiave del proprietario. Non avviare iscrizioni a pagamento o creare chiavi senza gli accessi/autorizzazioni necessari. Config e `.p8` restano private con mode 0600; il solo Hub usa la chiave. L'installer rc.4 ora conserva `--apns-config` fra upgrade; un servizio già avviato richiede il restart per applicare una nuova unità. Verificare ricezione con app chiusa e tap sulla sessione corretta, senza contenuti sensibili sul lock screen.

## Contratti da preservare durante il redesign

- Un Hub, una Fleet e gli stessi servizi/dati/credenziali. Nessun secondo Hub o vecchio harness di produzione.
- Codex è la source of truth di thread, transcript e queue; niente transcript DB sul client o sul Relay Hub.
- Outbox e chat effimeri, bounded in RAM; non aggiungere persistenza del testo. Keychain contiene l'accesso, non la conversazione.
- ACK non equivale a completamento. Identità `clientUserMessageId/clientId`, non matching per testo o timestamp.
- Nessun resend automatico dopo un esito sconosciuto. Retry Steer conserva l'expected turn originale.
- Capability esplicite, macchina ONLINE e richiesta corrente gateano le azioni; il layout non può concedere controlli mancanti.
- Revoca/pausa/rimozione Relay non fermano Codex locale.
- Account esposto: solo kind/email/plan. Non inoltrare auth, refresh token o workspace routing.
- Nessun cambio rete Exon/Spark/Mac/Zima per sviluppo; nessun disturbo ad altri workload.
- Non committare origin privato, OTP, token, runtime DB, chiavi, team/profili Apple o risultati di test con contenuti privati.
- Mantenere RC finché le acceptance reali non sono completate. Non pubblicare una release finale sulla sola base di build/preview/PWA/fake push.

## Dev loop e verifiche

Progetto [native/CodexRelay.xcodeproj](native/CodexRelay.xcodeproj), schema `CodexRelay`, bundle `net.codex-relay.iphone`, iOS 17+. [Signing.xcconfig](native/Signing.xcconfig) carica opzionalmente `LocalSigning.xcconfig`, ignorato da Git. Conservare il team del proprietario nel file locale.

Il watcher locale già esistente è stato riavviato come unico processo con firma ad hoc e Keychain entitlement del simulatore. Ogni salvataggio in `native/` compila, installa e riavvia **solo il simulatore**. Non aggiorna automaticamente il telefono fisico. Non avviare watcher duplicati o cancellare dati/Keychain. Sospendere il watcher durante debug/XCUITest e ripristinarlo alla fine. L'iPhone riceve una nuova versione dopo build/install da Xcode; non è hot reload e la RAM viene azzerata mentre l'abbinamento resta nel Keychain.

Verifiche eseguite sulla base funzionale:

- `GOTOOLCHAIN=go1.27.1 make check build cross`: gofmt/vet, Go/race, nove test browser, quattro test installer, build e tre cross-build PASS.
- `swift test --package-path native`: dieci test core PASS.
- Build simulatore con firma locale, build-for-testing e live XCUITest contro il Hub reale PASS. Il test usa configurazione privata nel bundle di test costruito, mai nel repository; CI senza config non prova il live E2E.
- Build iPhone firmata, verifica strict della firma, installazione e avvio dell'ultima build PASS.
- Controllo finale del runtime: Hub attivo rc.4, SQLite `quick_check` OK, Exon/Spark/MacBook ONLINE e enrollment iPhone attivo. Controllo SSH separato: servizio Spark attivo, binario ancora rc.3. Nessun servizio riavviato per questo controllo.
- CI Go/native verde sulla base funzionale `1f4cf72` ([run verificato](https://github.com/mothx9/codex-relay/actions/runs/37492369716)); ricontrollare comunque HEAD prima della prossima wave. Il Native job compila anche il target UI test con `build-for-testing`.

Comandi e dettagli completi sono in [native/README.md](native/README.md), [DEPLOYMENT.md](DEPLOYMENT.md) e [VALIDATION.md](VALIDATION.md). Leggere anche README, ARCHITECTURE, DISCOVERY, SECURITY e HANDOFF_MACOS. L'handoff operativo privato contiene accessi e thread autorizzati; il suo stato rc.3 iniziale è storico e viene superato dal checkpoint rc.4 attuale.

Prima di iniziare: verificare branch, dirty work, remoto, CI, servizio esistente e stato del watcher. Procedere con piccoli incrementi, test pertinenti e commit/push. Non chiedere conferme per attività già autorizzate; chiedere soltanto azioni fisiche o accessi/permessi indispensabili.

## Risultato atteso dall'upgrade

Un'app iPhone usabile con una mano, leggibile e coerente, con composer/chat/Needs You/dispositivi e recovery completi; preview isolate per iterare rapidamente; verifiche reali sui flussi nativi; documentazione e CI aggiornate. La conclusione deve dire che cosa è stato implementato, che cosa è stato provato sul dispositivo e quali blocker esterni restano. Il collegamento appena ottenuto è la base per questa wave, non una ragione per lasciare la UI attuale invariata.
