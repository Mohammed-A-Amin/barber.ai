import ARKit
import SwiftUI

struct TryOnView: View {
    private var isFaceTrackingSupported: Bool {
        ARFaceTrackingConfiguration.isSupported
    }

    var body: some View {
        Group {
            if isFaceTrackingSupported {
                ZStack(alignment: .top) {
                    ARViewContainer()
                        .ignoresSafeArea()

                    StatusBadge(title: "Face tracking active")
                        .padding(.top, 16)
                }
                .background(Color.black)
            } else {
                UnsupportedFaceTrackingView()
            }
        }
        .navigationTitle("Try On")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TryOnView_Previews: PreviewProvider {
    static var previews: some View {
        TryOnView()
    }
}

private struct StatusBadge: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.black.opacity(0.7), in: Capsule())
    }
}

private struct UnsupportedFaceTrackingView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "faceid")
                .font(.system(size: 44))
                .foregroundStyle(.blue)

            Text("Face Tracking Unavailable")
                .font(.title3.weight(.semibold))

            Text("This feature requires a Face ID iPhone.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .background(Color(.systemGroupedBackground))
    }
}
