import ARKit
import RealityKit
import SwiftUI

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

        // Keep ARView creation separate from session startup so future work can
        // swap the debug attachment for a hairstyle model without changing the
        // SwiftUI surface area.
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
    @Published var attachmentStatus = "Awaiting hairstyle asset"

    var combinedStatus: String {
        "\(trackingStatus) · \(faceStatus)"
    }
}

final class FaceTrackingSessionController: NSObject {
    private weak var arView: ARView?
    private let sessionState: FaceTrackingSessionState
    private var faceAnchor: AnchorEntity?
    private let attachmentController = HairstyleAttachmentController()

    init(sessionState: FaceTrackingSessionState) {
        self.sessionState = sessionState
    }

    func prepare(arView: ARView) {
        self.arView = arView
        arView.session.delegate = self
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
        arView.renderOptions.insert(.disableMotionBlur)

        // This face anchor is the insertion point for future hairstyle entities.
        let faceAnchor = AnchorEntity(.face)
        let attachment = attachmentController.makeAttachmentEntity(statusHandler: { [weak self] status in
            Task { @MainActor in
                self?.sessionState.attachmentStatus = status
            }
        })
        faceAnchor.addChild(attachment)
        arView.scene.addAnchor(faceAnchor)
        self.faceAnchor = faceAnchor
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

private struct HairstyleAttachmentDescriptor {
    let resourceName: String
    let position: SIMD3<Float>
    let scale: SIMD3<Float>
    let orientation: simd_quatf

    static let placeholder = HairstyleAttachmentDescriptor(
        resourceName: "StarterHair.usdz",
        position: [0, 0.12, 0.02],
        scale: [1.0, 1.0, 1.0],
        orientation: simd_quatf(angle: 0, axis: [0, 1, 0])
    )
}

private final class HairstyleAttachmentController {
    private let descriptor = HairstyleAttachmentDescriptor.placeholder

    func makeAttachmentEntity(statusHandler: (String) -> Void) -> Entity {
        do {
            // This loads a bundled model by name. When a real hairstyle asset is
            // added to the app target, only the descriptor should need updating.
            let hairstyleEntity = try Entity.load(named: descriptor.resourceName)
            hairstyleEntity.name = "HairstyleAttachment"
            hairstyleEntity.position = descriptor.position
            hairstyleEntity.scale = descriptor.scale
            hairstyleEntity.orientation = descriptor.orientation
            statusHandler("Loaded hairstyle: \(descriptor.resourceName)")

            return hairstyleEntity
        } catch {
            statusHandler("Using debug marker: add \(descriptor.resourceName) to the app bundle")
            return makeDebugAttachmentEntity()
        }
    }

    private func makeDebugAttachmentEntity() -> Entity {
        // This temporary marker sits where a hairstyle root should be attached.
        let mesh = MeshResource.generateSphere(radius: 0.035)
        let material = SimpleMaterial(color: .systemTeal, roughness: 0.2, isMetallic: false)
        let marker = ModelEntity(mesh: mesh, materials: [material])
        marker.name = "FaceDebugMarker"
        marker.position = [0, 0.09, 0.06]

        return marker
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
