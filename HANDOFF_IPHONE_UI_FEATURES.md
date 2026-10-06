# Handoff: upgrade nativo iPhone, UI e feature

Checkpoint: 6 ottobre 2026. Repository esistente: https://github.com/mothx9/codex-relay, branch `main`. Base funzionale della review iniziale: `1f4cf72`; una prima implementazione successiva della chat iPhone è descritta sotto. Non ricreare il progetto.

## Richiesta attuale del proprietario

L'app è stata firmata, installata, aperta e abbinata sul vero iPhone. Il proprietario considera l'interfaccia attuale provvisoria e chiede un'interfaccia pensata davvero per iPhone, insieme a un upgrade delle feature. La prossima wave deve progettare e implementare questo upgrade, preservando il sistema già collegato e distinguendo le funzioni presenti dalle acceptance ancora mancanti.

Il nuovo controllo vede tutti e tre gli host ONLINE con agent rc.4 e metadata account. Spark è stato aggiornato separatamente. La chat iPhone del riferimento fornito dal proprietario è implementata; APNs reale non è configurato. Il collegamento dell'iPhone non significa che ogni flusso nativo sia già verificato.

## Stato verificato

| Area | Stato concreto |
| --- | --- |
| Hub | L'unico Hub Zima esistente è stato aggiornato in place a rc.4. Stesso servizio e directory dati; DB, bootstrap, credenziali e VAPID preservati. |
| Rollback | Backup privato di binario, unità e SQLite. Un primo controllo di recovery fallito ha realmente ripristinato rc.3; il successivo upgrade rc.4 è riuscito. |
| Exon | Agent rc.4 aggiornato separatamente, con snapshot e account metadata. Codex non è stato riavviato. |
| MacBook | Agent rc.4 aggiornato separatamente attraverso il launchd esistente; credenziali e plist preservati. |
| Spark | Era offline durante il primo upgrade. Ora agent rc.4 linux/arm64 aggiornato in place, adapter/Hub collegati e metadata account presenti. Token e unità preservati; daemon Codex condiviso non riavviato. |
| Controlli PWA precedenti | New Turn, Follow-up con riconciliazione esatta, Answer e recovery agent/Hub erano passati su tutti e tre gli host attraverso questo stesso Hub. Steer e Interrupt erano passati su Exon. Sono prove storiche della base, non acceptance del nuovo client nativo. |
| OTP sul Hub reale | Otto cifre, exchange riuscito, riuso rifiutato, scadenza reale dopo cinque minuti. Nessun token amministratore sul telefono. |
| Revoca e dispositivi | Su enrollment usa-e-getta: revoca operatore chiude WSS e produce HTTP 401; rimozione client; aggiunta agent, conflitto, pausa/ripresa, revoca, re-enrollment e rimozione. Nessun enrollment reale revocato per le prove. |
| App fisica | Personal Team del proprietario, Developer Mode confermata dopo il riavvio, profilo rigenerato per l'iPhone collegato, firma verificata, installazione e avvio riusciti. Il proprietario ha confermato pairing e apertura. |
| Ultime correzioni sull'iPhone | La nuova chat e le card delle domande asincrone sono state firmate, installate e avviate. Firma strict verificata. La ricezione di una nuova domanda reale sul telefono resta da osservare. |
| Native E2E nel simulatore | Hub HTTPS reale: pairing, Fleet dei tre host registrati, Keychain dopo riavvio del processo, New Turn sul thread isolato, risposta Codex fresca, un solo messaggio utente canonico, nessun duplicato ottimistico, foreground reconnect. Suite ripassata dopo le ultime correzioni. |
| Form native | Domande strutturate e approval comando/file; aggiunte review completa dei permessi e form MCP con campi tipizzati/schema/JSON. La live acceptance di queste form è ancora aperta. |
| Preview | Sette preview SwiftUI isolate, inclusa la chat di riferimento con domanda/opzioni. Test UI con cronologia lunga, composer/tastiera, dettaglio Terminale e draft conservato. Nessun accesso a Keychain/Hub/notifiche dalle fixture. |
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
| `259ae9b` | Titolo/opzioni delle domande canoniche asincrone conservati in adapter e protocollo; routing live/history e budget RAM Hub testati. |
| `9323554` | Chat iPhone, Markdown, card tool/domande, composer fisso, preview di riferimento e test UI/core. |
| `39e3b5f` | Testo e domande condividono il limite byte della singola attività. |
| `d3c68c3` | Riga composer separata dal transcript, posizione iniziale sugli ultimi messaggi e test che esclude sovrapposizione con il messaggio accodato. |
| `0e5422c` | Posizionamento iniziale dopo il layout della destinazione di navigazione; corretta la partenza intermittente lontano dagli ultimi messaggi. |

## Review dell'app attuale

Aggiornamento successivo al report iniziale: il proprietario ha fornito un riferimento per la chat iPhone. È stato implementato in [SessionView.swift](native/iOS/SessionView.swift): header compatto titolo/macchina/progetto, messaggi Codex a sinistra e utente a destra, Markdown nativo, card Terminale/MCP apribili, badge Follow-up in coda e composer fisso sopra la tastiera. Il composer usa Liquid Glass su iOS 26+ con fallback material; Steer/Interrupt restano espliciti nel menu. La preview di riferimento e il test con cronologia lunga sono isolati dal Hub. I punti 1 e 2 della review iniziale qui sotto sono quindi già affrontati da questa prima wave; Fleet, dispositivi, richieste e gli altri gap rimangono nel backlog. Le card non mostrano «completati»: il protocollo attuale non espone l'esito di ogni tool.

Questa è una review del codice e delle prove disponibili, non una certificazione visiva completa del vero iPhone. Il proprietario ha già espresso chiaramente che la UI va rifatta. I flussi non ancora provati fisicamente restano aperti anche quando il backend/PWA ha prove storiche positive.

### Domanda YVEX su Spark non arrivata in Relay

La lettura non invasiva del daemon Spark ha confermato una domanda canonica in `agentMessage.questions`. Adapter Go e DTO Swift ignoravano quel campo: ora preservano titolo/opzioni, mantengono anche i messaggi senza testo e mostrano una card nella chat. Il payload è limitato e il contenuto delle domande conta nei budget RAM del Hub e del client. Test adapter, routing Hub history/live e decodifica/presentazione Swift coprono il nuovo contratto. Hub e tre agent sono stati aggiornati in place, uno alla volta, preservando dati, token e servizi esistenti.

Il rollout originale indica che quella domanda era già stata risposta dal client Codex. La verifica reale di history via Hub restituisce 24 attività normalizzate dal limite di 40 item grezzi, senza la vecchia domanda: è fuori dalla finestra recente. Nessun comando o risposta è stato inviato al thread YVEX. Non dichiarare che quella domanda sia ora pending o già visibile sul telefono.

Questo intervento completa il trasporto/presentazione del contenuto disponibile, non la risposta asincrona. Le domande nonblocking non sono il server RPC `requestUserInput`: nello schema locale verificato non è stato qualificato un canale dedicato di risposta/risoluzione. Non creare un pending RPC o `CanAnswer` artificiale, né usare un Follow-up come se fosse una risposta canonica. Priorità per la prossima wave: qualificare il reply ufficiale, lo stato risolto da altro client e la scoperta di domande quando la sessione non è aperta o la domanda esce dalla finestra recente. APNs ad app chiusa è un'acceptance distinta, ancora bloccata sugli input Apple.

| Priorità | Riscontro e conseguenza | Intervento richiesto |
| --- | --- | --- |
| Affrontata | La precedente chat metteva composer e azioni sotto tutta la cronologia. [SessionView](native/iOS/SessionView.swift) ora mantiene il composer in una riga fissa sotto il transcript, rispettando safe area e tastiera, con scroll iniziale, controllo degli aggiornamenti e ritorno ai messaggi recenti. | Test tastiera/cronologia lunga PASS; completare Dynamic Type, telefono piccolo, orientamento e uso fisico. |
| Affrontata | Il monospazio generalizzato è stato sostituito da typography nativa e Markdown. Output/codice restano monospaziati e le attività sono in card con dettagli selezionabili. | Preview e test dettagli PASS; completare la review visiva fisica e la copertura dei diversi tipi di attività reali. |
| Alta | La Fleet è una lista piatta con filtri orizzontali e ricerca. Il nativo non implementa il grouping descritto per la PWA e non ha una inbox autonoma delle richieste. | Navigazione progettata per iPhone: Fleet, attenzione/Needs You e impostazioni/dispositivi; priorità alle richieste actionable, distinzione immediata fra host offline e stato del turno. |
| Alta | [logout](native/iOS/RelayController.swift) ignora il fallimento della richiesta server e dimentica comunque la credenziale locale. La UI promette «Esci e revoca» anche senza conferma di revoca. | Distinguere uscita locale e revoca confermata; non dichiarare revoca riuscita quando il Hub è irraggiungibile. Recovery esplicita e test del caso offline. |
| Media | `busy` copre soprattutto pairing; varie mutazioni dispositivi non hanno loading/disabled/error contestuali. I codici mostrano «valido 5 minuti» statico, senza usare la scadenza per lo stato della UI. | Stato per operazione, prevenzione dei doppi tap, esito leggibile, countdown/scadenza reale e generazione di un nuovo codice. |
| Media | [DevicesView](native/iOS/Views.swift) permette pausa/ripresa e rimozione macchina, e revoca operatore. Non espone revoca macchina separata o rimozione operatore, benché il backend le supporti. | Completare i flussi API esistenti con distinzione fra sospensione, revoca e rimozione; conferme contestuali e stato di questo iPhone. Codex deve continuare localmente. |
| Media | Le form permissions/MCP sono funzionali ma la review è ancora testo JSON e i form complessi richiedono editor JSON. | Form native più chiare, riepilogo di host/progetto/operazione/scope, evidenza dei campi obbligatori, errori locali e fallback locale esplicito per gli schemi non supportati. |
| Media | [MCPResponse](native/RelayCore/Models.swift) è un validatore custom di un sottoinsieme JSON Schema; usa numeri Double e non copre ogni keyword. | Fixture del protocollo effettivo, controllo delle keyword non supportate e della precisione numerica. Non presentarlo come validatore JSON Schema universale. Validare anche l'interazione live. |
| Media | Il tema è forzato scuro, varie superfici usano il bianco fisso e molte label sono tecniche o mescolano lingue. | Tema/adattamento di sistema, contrasto, Dynamic Type, VoiceOver, touch target, stati di focus, testo coerente e comprensibile. Verificare telefono piccolo, orientamento e tastiera. |
| Media | [Notifications.swift](native/iOS/Notifications.swift) inoltra il tap a un callback opzionale senza un buffer esplicito; il controller apre l'ID anche prima di avere la snapshot. | Verificare cold start, autenticazione mancante, sessione assente e sheet già aperta. Routing centralizzato, destinazione valida e stato di caricamento, senza perdita del tap. Il rischio viene dalla lettura del codice; il bug non è ancora riprodotto su APNs reale. |
| Media | Stato notifiche e token sono in parte RAM; non viene ricostruito interamente lo stato del consenso/registrazione a ogni avvio. | Leggere lo stato iOS, separare consenso da configurazione Hub e registrazione del device, gestire rinnovo token/riavvio e rendere visibile lo stato effettivo. |
| Media | Il dettaglio chat è stato separato in [SessionView.swift](native/iOS/SessionView.swift). Fleet, dispositivi, richieste e fixture restano in [Views.swift](native/iOS/Views.swift); routing, transport e mutazioni condividono un controller unico. | Continuare la separazione quanto serve al redesign, senza creare un framework o un nuovo orchestratore. Conservare RelayCore e i contratti esistenti. |

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
| Domanda asincrona: titolo/opzioni nel contesto | Contratto Go/Hub/Swift e fixture UI PASS; vecchia domanda Spark fuori dalla finestra recente | Build installata; nuova domanda reale da osservare |
| Domanda asincrona: reply, risoluzione e attenzione fuori dalla chat aperta | Aperta, distinto da Answer RPC | Aperta |
| Permissions/MCP live | Aperta; core/contratti non sono E2E | Aperta |
| Steer, stale TURN_CHANGED, Interrupt | Aperta; intent retention corretta e testata nel core | Aperta |
| Foreground reconnect | PASS | Aperta |
| UNKNOWN_OUTCOME senza resend automatico | Core/contratto presenti; E2E da completare | Aperta |
| Recovery app/agent/Hub con il nuovo nativo | Parziale; prove storiche PWA non trasferibili | Aperta |
| Sleep/wake e roaming | Richiedono collaborazione fisica del proprietario | Aperta |
| APNs con app chiusa e tap corretto, anche cold start | Il simulatore/fake provider non basta | Bloccata su team/capability/chiavi del proprietario |

Usare soltanto i thread di validation isolati indicati nell'handoff operativo privato. Non inviare comandi ai thread di lavoro ordinari. Non riavviare i daemon Codex condivisi per comodità.

### 4. Spark e APNs

Spark è stato aggiornato a rc.4 con backup/rollback e token conservato. Tutte e tre le macchine hanno adapter/Hub collegati e metadata account; il controllo reale vede i tre host ONLINE. Ricontrollare lo stato prima della prossima wave. Nessuna modifica di rete e nessun restart del daemon Codex condiviso.

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

Verifiche eseguite, incluse la nuova chat e il trasporto delle domande:

- `GOTOOLCHAIN=go1.27.1 make check build cross`: gofmt/vet, Go/race, nove test browser, quattro test installer, build e tre cross-build PASS.
- `swift test --package-path native`: quattordici test core PASS.
- Build simulatore con firma locale, build-for-testing e live XCUITest contro il Hub reale PASS. Il test usa configurazione privata nel bundle di test costruito, mai nel repository; CI senza config non prova il live E2E.
- Build iPhone firmata, verifica strict della firma, installazione e avvio dell'ultima build PASS.
- Controllo runtime: Hub attivo rc.4, SQLite `quick_check` OK, Exon/Spark/MacBook aggiornati separatamente a rc.4, ONLINE e con metadata account. Tutti gli enrollment, incluso un ulteriore enrollment già presente, sono stati conservati; nessun record sconosciuto rimosso.
- CI Go/native verde sulla base funzionale `1f4cf72` ([run verificato](https://github.com/mothx9/codex-relay/actions/runs/37492369716)); ricontrollare comunque HEAD prima della prossima wave. Il Native job compila anche il target UI test con `build-for-testing`.

Comandi e dettagli completi sono in [native/README.md](native/README.md), [DEPLOYMENT.md](DEPLOYMENT.md) e [VALIDATION.md](VALIDATION.md). Leggere anche README, ARCHITECTURE, DISCOVERY, SECURITY e HANDOFF_MACOS. L'handoff operativo privato contiene accessi e thread autorizzati; il suo stato rc.3 iniziale è storico e viene superato dal checkpoint rc.4 attuale.

Prima di iniziare: verificare branch, dirty work, remoto, CI, servizio esistente e stato del watcher. Procedere con piccoli incrementi, test pertinenti e commit/push. Non chiedere conferme per attività già autorizzate; chiedere soltanto azioni fisiche o accessi/permessi indispensabili.

## Risultato atteso dall'upgrade

Un'app iPhone usabile con una mano, leggibile e coerente, con composer/chat/Needs You/dispositivi e recovery completi; preview isolate per iterare rapidamente; verifiche reali sui flussi nativi; documentazione e CI aggiornate. La conclusione deve dire che cosa è stato implementato, che cosa è stato provato sul dispositivo e quali blocker esterni restano. Il collegamento appena ottenuto è la base per questa wave, non una ragione per lasciare la UI attuale invariata.
