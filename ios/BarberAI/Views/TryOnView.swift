import SwiftUI

struct TryOnView: View {
    private let cameraKitConfiguration = CameraKitConfiguration.fromBundle

    var body: some View {
        ZStack {
            CameraKitContainerView(configuration: cameraKitConfiguration)
                .ignoresSafeArea()
                .background(Color.black)

            ARAssistantOverlayView(
                context: BarberAIAPI.StyleContext(
                    activeLensId: cameraKitConfiguration.lensIDs.first,
                    activeStyle: "Hair Example",
                    hairColor: nil
                )
            )
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
