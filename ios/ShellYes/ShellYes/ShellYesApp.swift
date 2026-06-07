import SwiftUI

@main
struct ShellYesApp: App {
    @SwiftUI.State private var settings: SettingsStore
    @SwiftUI.State private var store: GameStore

    init() {
        let s = SettingsStore()
        _settings = .init(initialValue: s)
        _store = .init(initialValue: GameStore(settings: s))
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                SplashView(store: store, settings: settings)
            }
            .preferredColorScheme(settings.colorMode.preferredScheme)
        }
    }
}
