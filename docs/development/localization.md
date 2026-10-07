# Native localization

English is the source language. The native app ships Italian translations in
[`Localizable.xcstrings`](../../native/RelayCore/Resources/Localizable.xcstrings).
The same catalog is compiled into the iPhone app and the `RelayCore` test bundle.
`relayLocalizationBundle` selects the correct bundle for those two builds.

Use `String(localized: ..., bundle: relayLocalizationBundle)` for computed
labels, status/error text and interpolated strings. SwiftUI literal labels may
also use the catalog directly. Never localize wire enum values, JSON keys,
credentials, service/Keychain identifiers, paths, URLs or user/model content.
Unknown runtime error/content text is displayed as supplied by its source.

Add English keys and Italian translations together. Preserve interpolation
placeholder types (`%lld`, `%@`) and literal percent escapes. Missing values must
still be unavailable, not zero. Product status text remains separate from the
canonical protocol state.

Run `swift test --package-path native` and the isolated English/Italian
onboarding UI tests. Review Italian and accessibility text sizes on iPhone 16;
longer labels must wrap or adapt without hiding the primary action. Live tests
reuse an existing development controller; they never create production
enrollments just to exercise localization.

SwiftPM toolchains that do not compile String Catalogs use generated `.strings`
resources. After editing the catalog, run `python3 scripts/localization.py`. CI
checks that these resources match the catalog; the Xcode app compiles the catalog
directly.
