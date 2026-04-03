import SwiftUI

struct PlaceholderScreen: View {
    let title: String

    var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.title)
                .fontWeight(.semibold)

            Text("Placeholder screen")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

#Preview {
    PlaceholderScreen(title: "Example")
}
