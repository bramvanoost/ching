import SwiftUI

struct SplashView: View {
    let store: GameStore
    let settings: SettingsStore

    @SwiftUI.State private var logoVisible: Bool = false
    @SwiftUI.State private var actionsVisible: Bool = false

    var body: some View {
        ZStack {
            Background()

            VStack(spacing: 0) {
                Spacer()

                // Big lowercase logo
                HStack(spacing: 0) {
                    Text("c")
                        .foregroundStyle(Color.ink)
                    Text("h")
                        .foregroundStyle(Color.coral)
                        .font(.avenir(108, weight: .demiBold))
                    Text("ing")
                        .foregroundStyle(Color.ink)
                }
                .font(.avenir(108, weight: .ultraLight))
                .tracking(6)
                .opacity(logoVisible ? 1 : 0)
                .scaleEffect(logoVisible ? 1 : 0.92)

                Text("a push-your-luck dice game")
                    .font(.avenir(14, weight: .medium, italic: true))
                    .tracking(2)
                    .foregroundStyle(Color.ink.opacity(0.6))
                    .padding(.top, 6)
                    .opacity(logoVisible ? 1 : 0)

                Spacer()

                VStack(spacing: 18) {
                    NavigationLink {
                        GameView(store: store, settings: settings)
                            .onAppear {
                                store.newGame()
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
                .padding(.bottom, 60)
            }
            .padding(.horizontal, 24)
        }
        .navigationBarHidden(true)
        .task {
            withAnimation(.easeOut(duration: 0.7)) {
                logoVisible = true
            }
            try? await Task.sleep(nanoseconds: 350_000_000)
            withAnimation(.easeOut(duration: 0.5)) {
                actionsVisible = true
            }
        }
    }
}
