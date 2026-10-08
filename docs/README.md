# Codex Relay documentation

Start with the [product overview](../README.md). Choose the guide for what you
want to do; you do not need the implementation reports to install Relay.

## Understand

- [Architecture and source-of-truth boundaries](architecture/overview.md)
- [Native navigation and entity homes](architecture/native-navigation.md)
- [Canonical protocol](architecture/protocol.md) and [synchronization](architecture/synchronization.md)
- [Codex account data](architecture/accounts.md) and [notification behavior](architecture/notifications.md)
- [Current status, distribution and compatibility](status.md)

## Install

Start with [downloads and the shortest installation path](setup/downloads.md).

1. [Linux Hub](setup/hub.md)
2. [iPhone download and pairing](setup/iphone.md)
3. [Linux Agent](setup/linux-agent.md) or [macOS Agent](setup/macos-agent.md)
4. [Native notification setup](setup/notifications.md)

## Operate

- [Upgrade safely](operations/upgrading.md)
- [Troubleshoot and collect diagnostics](operations/troubleshooting.md)
- [Controllers, enrollment and recovery](architecture/access.md)

## Develop

- [Contributing](../CONTRIBUTING.md)
- [Native iOS and screenshots](development/native-ios.md)
- [Testing](development/testing.md) and [test isolation](development/test-isolation.md)
- [Localization](development/localization.md)
- [Release engineering](development/releases.md)
- [Provider boundary](architecture/provider-boundary.md)

## Security

Read [SECURITY.md](../SECURITY.md) before exposing a Hub. Relay credentials grant
control of local Codex work; OpenAI credentials stay on workers.

## Engineering reference

Dated evidence: [v0.1.0](development/validation/v0.1.0.md), [M1](development/validation/m1-validation.md),
[M2](development/validation/m2-validation.md),
[live event audit](development/validation/live-event-audit.md).
[Historical records](development/history/README.md) preserve earlier investigations.
