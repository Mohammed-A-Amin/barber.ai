import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            AppTab(title: "Login", systemImage: "person.crop.circle") {
                LoginView()
            }

            AppTab(title: "Try On", systemImage: "camera.viewfinder") {
                TryOnView()
            }

            AppTab(title: "Catalog", systemImage: "square.grid.2x2") {
                CatalogView()
            }

            AppTab(title: "Chat", systemImage: "bubble.left.and.bubble.right") {
                ChatView()
            }

            AppTab(title: "Profile", systemImage: "person") {
                ProfileView()
            }
        }
    }
}

private struct AppTab<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            content
        }
        .tabItem {
            Label(title, systemImage: systemImage)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
