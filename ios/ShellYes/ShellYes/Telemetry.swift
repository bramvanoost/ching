import Foundation
#if canImport(Aptabase)
import Aptabase
#endif

/// Thin wrapper around the Aptabase Swift SDK so the rest of the app
/// calls `Telemetry.shared.track(...)` without caring which backend
/// handles it.
///
/// The `#if canImport(Aptabase)` guard means the file builds either
/// with OR without the SPM package present. Once you've added
/// `https://github.com/aptabase/aptabase-swift` via Xcode's File →
/// Add Package Dependencies, the real SDK calls activate. Until
/// then, events log to console in DEBUG and drop in release.
@MainActor
final class Telemetry {
    static let shared = Telemetry()

    private var initialized = false

    private init() {}

    /// Called once at app launch from `ShellYesApp.init()`.
    func initialize(appKey: String?) {
        guard let appKey, !appKey.isEmpty else { return }
        #if canImport(Aptabase)
        Aptabase.shared.initialize(
            appKey: appKey,
            options: InitOptions(host: "https://aptabase.fastronaut.com")
        )
        #endif
        initialized = true
    }

    /// Fire-and-forget event. Props are coerced to strings server-side
    /// by the Aptabase SDK.
    func track(_ event: String, props: [String: Any] = [:]) {
        #if DEBUG
        print("[Telemetry] \(event) \(props)")
        #endif
        guard initialized else { return }
        #if canImport(Aptabase)
        // Aptabase's `trackEvent` expects `[String: Any]?` — same shape.
        Aptabase.shared.trackEvent(event, with: props)
        #endif
    }
}
