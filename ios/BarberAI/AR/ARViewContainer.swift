import ARKit
import RealityKit
import SwiftUI

struct ARViewContainer: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(
            frame: .zero,
            cameraMode: .ar,
            automaticallyConfigureSession: false
        )

        // Keep ARView creation separate from session startup so future work can
        // add face-anchored hairstyle entities without rewriting TryOnView.
        context.coordinator.sessionController.prepare(arView: arView)
        context.coordinator.sessionController.startFaceTracking()

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        // SwiftUI state does not drive AR changes yet.
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        coordinator.sessionController.pause()
    }

    final class Coordinator {
        let sessionController = FaceTrackingSessionController()
    }
}

final class FaceTrackingSessionController {
    private weak var arView: ARView?

    func prepare(arView: ARView) {
        self.arView = arView
        configureScene()
    }

    func startFaceTracking() {
        guard ARFaceTrackingConfiguration.isSupported, let arView else {
            return
        }

        let configuration = ARFaceTrackingConfiguration()
        configuration.isLightEstimationEnabled = true

        arView.session.run(
            configuration,
            options: [.resetTracking, .removeExistingAnchors]
        )
    }

    func pause() {
        arView?.session.pause()
    }

    private func configureScene() {
        guard let arView else {
            return
        }

        arView.environment.sceneUnderstanding.options = []

        // Future step: create a face anchor and attach hairstyle content here.
    }
}
