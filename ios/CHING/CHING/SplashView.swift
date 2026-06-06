import SwiftUI

struct SplashView: View {
    let store: GameStore
    let settings: SettingsStore

    @SwiftUI.State private var logoVisible: Bool = false
    @SwiftUI.State private var actionsVisible: Bool = false
    @SwiftUI.State private var creditVisible: Bool = false

    private var creditAttributed: AttributedString {
        let raw = "Sound effect by [Alfarran Basalim](https://pixabay.com/users/farran_ez-45967570/?utm_source=link-attribution&utm_medium=referral&utm_campaign=music&utm_content=456148) from [Pixabay](https://pixabay.com/?utm_source=link-attribution&utm_medium=referral&utm_campaign=music&utm_content=456148)."
        return (try? AttributedString(markdown: raw)) ?? AttributedString(raw)
    }

    var body: some View {
        ZStack {
            Background()

            VStack(spacing: 0) {
                Spacer()

                // Big lowercase logo — the "y" in yes is the punchline letter.
                HStack(spacing: 0) {
                    Text("shell ")
                        .foregroundStyle(Color.ink)
                    Text("y")
                        .foregroundStyle(Color.coral)
                        .font(.avenir(78, weight: .demiBold))
                    Text("es")
                        .foregroundStyle(Color.ink)
                }
                .font(.avenir(78, weight: .ultraLight))
                .tracking(5)
                .opacity(logoVisible ? 1 : 0)
                .scaleEffect(logoVisible ? 1 : 0.92)

                Text("push your luck. score the shore.")
                    .font(.avenir(14, weight: .medium, italic: true))
                    .tracking(2)
                    .textCase(.lowercase)
                    .foregroundStyle(Color.ink.opacity(0.6))
                    .padding(.top, 6)
                    .opacity(logoVisible ? 1 : 0)

                VStack(spacing: 18) {
                    NavigationLink {
                        GameView(store: store, settings: settings)
                            .onAppear {
                                store.newGame()
                                AudioPolicy.shared.setInGame(true)
                            }
                            .onDisappear {
                                AudioPolicy.shared.setInGame(false)
                            }
                    } label: {
                        Text("New Game")
                    }
                    .stampButton(primary: true, invite: true)
                    .frame(maxWidth: 280)

                    NavigationLink {
                        SettingsView(settings: settings, onNewGame: { store.newGame() })
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 12, weight: .light))
                            Text("settings")
                                .font(.avenir(13, weight: .medium, italic: true))
                                .tracking(2)
                                .textCase(.lowercase)
                        }
                        .foregroundStyle(Color.ink.opacity(0.5))
                        .padding(.vertical, 10)
                        .padding(.horizontal, 18)
                    }
                }
                .opacity(actionsVisible ? 1 : 0)
                .offset(y: actionsVisible ? 0 : 12)
                .padding(.top, 36)

                Spacer()

                // Pixabay attribution per their license terms.
                Text(creditAttributed)
                    .font(.avenir(10, weight: .medium, italic: true))
                    .tracking(0.5)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.ink.opacity(0.42))
                    .tint(Color.coral.opacity(0.85))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 18)
                    .opacity(creditVisible ? 1 : 0)
            }
            .padding(.horizontal, 24)
        }
        .navigationBarHidden(true)
        .task {
            AudioPolicy.shared.setInGame(false)
            withAnimation(.easeOut(duration: 0.7)) {
                logoVisible = true
            }
            try? await Task.sleep(nanoseconds: 350_000_000)
            withAnimation(.easeOut(duration: 0.5)) {
                actionsVisible = true
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
            withAnimation(.easeOut(duration: 0.6)) {
                creditVisible = true
            }
        }
    }
}
