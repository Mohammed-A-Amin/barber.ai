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

                    if sessionState.showHairMask, let overlay = sessionState.hairMaskOverlay {
                        Image(uiImage: overlay)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFill()
                            // MediaPipe's mask texture arrives upside down relative to
                            // the AR preview, so flip it vertically before compositing.
                            .scaleEffect(x: 1, y: -1)
                            // The AR preview and segmentation buffer are slightly offset
                            // horizontally after aspect-fill compositing on device.
                            .offset(x: -60)
                            .ignoresSafeArea()
                            .allowsHitTesting(false)
                    }

                    VStack {
                        StatusBadge(title: sessionState.trackingStatus)
                            .padding(.top, 16)

                        Spacer()

                        SegmentationControlPanel(sessionState: sessionState)
                            .padding(.horizontal, 20)
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

private struct SegmentationControlPanel: View {
    @ObservedObject var sessionState: FaceTrackingSessionState

    var body: some View {
        Toggle(isOn: $sessionState.showHairMask) {
            EmptyView()
        }
        .labelsHidden()
        .tint(.red)
    }
}
