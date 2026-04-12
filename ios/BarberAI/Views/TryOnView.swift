import SwiftUI

struct TryOnView: View {
    private let cameraKitConfiguration = CameraKitConfiguration.fromBundle

    var body: some View {
        CameraKitContainerView(configuration: cameraKitConfiguration)
            .ignoresSafeArea()
            .background(Color.black)
            .navigationTitle("Try On")
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct TryOnView_Previews: PreviewProvider {
    static var previews: some View {
        TryOnView()
    }
}
