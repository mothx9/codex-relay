import Foundation

/// The core is compiled into the app target and also tested as a Swift package.
/// Both builds use the same English-source String Catalog and Italian resources.
public let relayLocalizationBundle: Bundle = {
    #if SWIFT_PACKAGE
    Bundle.module
    #else
    Bundle.main
    #endif
}()
