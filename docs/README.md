# Codex Relay documentation

Start with the [product overview](../README.md), then follow the guide for each role.

| Goal | Guide |
| --- | --- |
| Understand the system | [Architecture](architecture/overview.md), [trust and security](../SECURITY.md) |
| Install the always-on coordinator | [Linux Hub](setup/hub.md) |
| Connect a Codex-running machine | [Linux Agent](setup/linux-agent.md), [macOS Agent](setup/macos-agent.md) |
| Install the controller | [iPhone build and pairing](setup/iphone.md) |
| Understand synchronization | [Canonical state and recovery](architecture/synchronization.md) |
| Integrate a client | [Relay protocol](architecture/protocol.md) |
| Manage access | [Controllers, enrollment and recovery](architecture/access.md) |
| Understand runtime accounts | [Account registry](architecture/accounts.md) |
| Enable notifications | [APNs and Web Push](architecture/notifications.md) |
| Maintain the installation | [Upgrades](operations/upgrading.md), [troubleshooting](operations/troubleshooting.md) |
| Contribute | [Contributing](../CONTRIBUTING.md), [native development](development/native-ios.md), [testing](development/testing.md) |
| Prepare a release | [Release engineering](development/releases.md) |

Evidence is versioned: [M1 validation](m1-validation.md) records the completed
reliability baseline; [M2 product validation](m2-validation.md) records product
acceptance and the remaining physical/Apple gates. The [live event audit](live-event-audit.md) distinguishes
supported protocol events from observed acceptance. [Historical records](development/history/README.md)
are preserved for investigation, not as the normal setup path.
