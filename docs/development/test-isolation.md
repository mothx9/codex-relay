# Test isolation

## Default automated checks

Go Hub tests create `httptest` servers and temporary SQLite databases. Pairing,
revocation, controller removal and notification registration tests operate only
on those isolated stores. Swift presentation/reducer tests and previews require
no Hub, Keychain credentials or APNs. These checks can run without lab access.

## Optional live native acceptance

Use one explicitly enrolled development controller on the chosen simulator.
Reuse its Keychain enrollment across launches and test runs. Do not generate a
fresh production pairing code or controller for each test. Live XCUITest skips
when an existing paired controller is absent; it does not redeem a code by
itself. This also prevents a stale pairing configuration from silently creating
another production controller.

Supply `AcceptanceConfig.json` only inside the **built test bundle**, never the
repository. The configured origin and session identifiers are private. Read-only
navigation tests may inspect real sessions. Mutation tests require the
explicitly owned `Relay live validation` thread and `sendTurn: true`. Reuse that
thread and archive it after acceptance. Never answer or interrupt real project
work to exercise the UI.

Pause the single simulator watcher while running XCUITest, and resume it in a
`finally` cleanup block. Do not start a second watcher or erase the simulator
Keychain. Screenshots from a real deployment are private evidence and must not
be copied into public documentation; the public screenshot pipeline uses
sanitized fixtures.

## Controller cleanup

Controller names alone are insufficient proof that an enrollment is disposable.
Compare its exact identity, known test origin, creation time and last-seen time;
exclude the physical iPhone and current development simulator. Re-read the
registry immediately before removal, and abort if the candidate has changed or
become active. The authenticated removal endpoint also removes notification
registrations. Never clean controllers with a broad name-pattern deletion.

M2 reference-deployment hygiene removed three confirmed historical simulator
acceptance enrollments after these checks. The physical iPhone and the current
iPhone 16 development simulator remain authorized. No new enrollment was
created by the M2 live navigation tests.
