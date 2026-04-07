import ARKit
import SwiftUI

struct TryOnView: View {
    @StateObject private var sessionState = FaceTrackingSessionState()

    private var isFaceTrackingSupported: Bool {
        ARFaceTrackingConfiguration.isSupported
    }

    var body: some View {
        Group {
            if isFaceTrackingSupported {
                ZStack {
                    ARViewContainer(sessionState: sessionState)
                        .ignoresSafeArea()

                    VStack {
                        StatusBadge(title: sessionState.combinedStatus)
                            .padding(.top, 16)

                        Spacer()

                        InstructionOverlay(message: sessionState.attachmentStatus)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 20)
                    }
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

private struct InstructionOverlay: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)

            Text("The face anchor pipeline is ready. Add a bundled `StarterHair.usdz` file to replace the debug marker.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
