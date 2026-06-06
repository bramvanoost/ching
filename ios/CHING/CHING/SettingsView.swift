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

struct StampSegmented<T: Hashable>: View {
    @Binding var selection: T
    let options: [T]
    let labelFor: (T) -> String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { idx in
                let value = options[idx]
                Button {
                    selection = value
                } label: {
                    Text(labelFor(value))
                        .font(.cochin(13))
                        .foregroundStyle(value == selection ? Color.paper : Color.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(value == selection ? Color.ink : Color.paper)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(labelFor(value)))
                .accessibilityAddTraits(value == selection ? .isSelected : [])

                if idx < options.count - 1 {
                    Rectangle()
                        .fill(Color.ink)
                        .frame(width: 1.5)
                }
            }
        }
        .overlay(
            Rectangle().strokeBorder(Color.ink, lineWidth: 1.5)
        )
        .fixedSize(horizontal: false, vertical: true)
    }
}
