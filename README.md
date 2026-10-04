# Codex Relay

A small personal control plane for Codex sessions across machines. Codex runs the work locally; Relay transports control and derived state. Go hub + outbound Go agents + embedded browser PWA. SQLite contains metadata only; conversation text stays ephemeral.

Codex Relay is an independent project, not affiliated with or endorsed by OpenAI.

```text
iPhone / Browser -- HTTPS + WSS --> Relay Hub (Zima)
                                    ^   ^   ^
                             outbound agent connections
                               Exon Spark MacBook
                                 |    |      |
                              local Codex app-server
```

Implementation and validation are in progress. See [DISCOVERY.md](DISCOVERY.md) for the tested protocol boundary. No network configuration is changed by this project.
