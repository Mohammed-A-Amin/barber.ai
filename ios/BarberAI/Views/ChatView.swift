import SwiftUI

struct ChatView: View {
    var body: some View {
        PlaceholderScreen(title: "Chat")
            .navigationTitle("Chat")
    }
}

struct ChatView_Previews: PreviewProvider {
    static var previews: some View {
        ChatView()
    }
}
