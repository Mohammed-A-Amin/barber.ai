import ARKit
import RealityKit
import SwiftUI
import UIKit

struct ARViewContainer: UIViewRepresentable {
    @ObservedObject var sessionState: FaceTrackingSessionState

    func makeCoordinator() -> Coordinator {
        Coordinator(sessionState: sessionState)
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(
            frame: .zero,
            cameraMode: .ar,
            automaticallyConfigureSession: false
        )

        context.coordinator.sessionController.prepare(arView: arView)
        context.coordinator.sessionController.startFaceTracking()

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.sessionController.setHairMaskEnabled(sessionState.showHairMask)
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        coordinator.sessionController.pause()
    }

    final class Coordinator {
        let sessionController: FaceTrackingSessionController

        init(sessionState: FaceTrackingSessionState) {
            self.sessionController = FaceTrackingSessionController(sessionState: sessionState)
        }
    }
}

@MainActor
final class FaceTrackingSessionState: ObservableObject {
    @Published var trackingStatus = "Starting face tracking"
    @Published var faceStatus = "Looking for face"
    @Published var segmentationStatus = "Hair mask disabled"
    @Published var showHairMask = false
    @Published var hairMaskOverlay: UIImage?
}

final class FaceTrackingSessionController: NSObject {
    private weak var arView: ARView?
    private let sessionState: FaceTrackingSessionState
    private let hairSegmentationManager = HairSegmentationManager()

    init(sessionState: FaceTrackingSessionState) {
        self.sessionState = sessionState
    }

    func prepare(arView: ARView) {
        self.arView = arView
        arView.session.delegate = self
        configureScene()
        configureSegmentationCallbacks()
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

    func setHairMaskEnabled(_ enabled: Bool) {
        hairSegmentationManager.setEnabled(enabled)
    }

    private func configureScene() {
        guard let arView else {
            return
        }

        arView.environment.sceneUnderstanding.options = []
        arView.renderOptions.insert(.disableMotionBlur)
    }

    private func configureSegmentationCallbacks() {
        hairSegmentationManager.onMaskOverlayUpdated = { [weak self] image in
            Task { @MainActor in
                self?.sessionState.hairMaskOverlay = image
            }
        }

        hairSegmentationManager.onStatusChanged = { [weak self] status in
            Task { @MainActor in
                self?.sessionState.segmentationStatus = status
            }
        }
    }

    @MainActor
    private func setTrackingStatus(_ value: String) {
        sessionState.trackingStatus = value
    }

    @MainActor
    private func setFaceStatus(_ value: String) {
        sessionState.faceStatus = value
    }
}

extension FaceTrackingSessionController: ARSessionDelegate {
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let trackingText: String

        switch camera.trackingState {
        case .normal:
            trackingText = "Tracking active"
        case .notAvailable:
            trackingText = "Tracking unavailable"
        case .limited(let reason):
            trackingText = "Limited: \(reason.description)"
        }

        Task { @MainActor in
            setTrackingStatus(trackingText)
        }
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        updateFaceTrackingState(from: anchors, isTracked: true)
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        updateFaceTrackingState(from: anchors, isTracked: true)
    }

    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        updateFaceTrackingState(from: anchors, isTracked: false)
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        hairSegmentationManager.process(frame: frame)
    }

    private func updateFaceTrackingState(from anchors: [ARAnchor], isTracked: Bool) {
        guard anchors.contains(where: { $0 is ARFaceAnchor }) else {
            return
        }

        let statusText = isTracked ? "Face anchor detected" : "Face lost"

        Task { @MainActor in
            setFaceStatus(statusText)
        }
    }
}

private extension ARCamera.TrackingState.Reason {
    var description: String {
        switch self {
        case .initializing:
            return "initializing"
        case .excessiveMotion:
            return "move more slowly"
        case .insufficientFeatures:
            return "find better lighting"
        case .relocalizing:
            return "relocalizing"
        @unknown default:
            return "unknown"
        }
    }
}
