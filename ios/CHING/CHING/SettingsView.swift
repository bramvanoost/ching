import SwiftUI

struct SettingsView: View {
    let settings: SettingsStore

    var body: some View {
        ZStack {
            Color.paper.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                Text("Settings")
                    .font(.bodoni(24))
                    .foregroundStyle(Color.ink)

                Text("Section bodies land in Task 8.")
                    .font(.cochinItalic(14))
                    .foregroundStyle(Color.dimInk)

                Spacer()
            }
            .padding(20)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.paper, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}
