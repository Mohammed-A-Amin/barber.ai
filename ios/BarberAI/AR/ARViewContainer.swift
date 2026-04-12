import AVFoundation
import SCSDKCameraKit
import SwiftUI
import UIKit

struct CameraKitContainerView: UIViewControllerRepresentable {
    let configuration: CameraKitConfiguration

    func makeUIViewController(context: Context) -> CameraKitViewController {
        CameraKitViewController(configuration: configuration)
    }

    func updateUIViewController(_ viewController: CameraKitViewController, context: Context) {
        viewController.update(configuration: configuration)
    }

    static func dismantleUIViewController(_ viewController: CameraKitViewController, coordinator: ()) {
        viewController.stop()
    }
}

struct CameraKitConfiguration: Equatable {
    let apiToken: String
    let lensIDs: [String]
    let lensGroupID: String

    static let apiTokenKey = "SCCameraKitAPIToken"
    static let lensIDKey = "BarberAICameraKitLensID"
    static let lensGroupIDKey = "BarberAICameraKitLensGroupID"

    static var fromBundle: CameraKitConfiguration {
        CameraKitConfiguration(
            apiToken: bundleString(for: apiTokenKey),
            lensIDs: lensIDs(from: bundleString(for: lensIDKey)),
            lensGroupID: bundleString(for: lensGroupIDKey)
        )
    }

    var isConfigured: Bool {
        isUsable(apiToken) && !lensIDs.isEmpty && isUsable(lensGroupID)
    }

    private static func bundleString(for key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
    }

    private static func lensIDs(from rawValue: String) -> [String] {
        rawValue
            .components(separatedBy: CharacterSet(charactersIn: ",; \n\t"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.contains("$(") && !$0.contains("REPLACE_") }
    }

    private func isUsable(_ value: String) -> Bool {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedValue.isEmpty
            && !trimmedValue.contains("REPLACE_")
            && !trimmedValue.contains("$(")
    }
}

final class CameraKitViewController: UIViewController {
    private let previewView = PreviewView()
    private let captureSession = AVCaptureSession()
    private let lensQueue = DispatchQueue(label: "ai.barber.camera-kit.lens", qos: .userInitiated)
    private var cameraKit: CameraKitProtocol?
    private var currentConfiguration: CameraKitConfiguration
    private var hasStarted = false
    private var appliedLensID: String?

    init(configuration: CameraKitConfiguration) {
        self.currentConfiguration = configuration
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        previewView.automaticallyConfiguresTouchHandler = true
        view = previewView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        startIfPossible()
    }

    func update(configuration: CameraKitConfiguration) {
        guard configuration != currentConfiguration else {
            return
        }

        currentConfiguration = configuration
        stop()
        startIfPossible()
    }

    func stop() {
        guard hasStarted else {
            return
        }

        captureSession.stopRunning()
        cameraKit?.lenses.processor?.clear { _ in }
        cameraKit?.stop()
        cameraKit = nil
        appliedLensID = nil
        hasStarted = false
    }

    private func startIfPossible() {
        guard currentConfiguration.isConfigured else {
            showConfigurationPlaceholder()
            return
        }

        clearPlaceholder()

        let session = Session(
            sessionConfig: SessionConfig(apiToken: currentConfiguration.apiToken),
            lensesConfig: LensesConfig(cacheConfig: CacheConfig(lensContentMaxSize: 150 * 1024 * 1024)),
            errorHandler: nil
        )
        let input = AVSessionInput(session: captureSession)
        let arInput = ARSessionInput()

        cameraKit = session
        session.add(output: previewView)
        session.start(input: input, arInput: arInput)
        currentConfiguration.lensIDs.forEach { lensID in
            session.lenses.repository.addObserver(
                self,
                specificLensID: lensID,
                inGroupID: currentConfiguration.lensGroupID
            )
        }

        DispatchQueue.global(qos: .userInitiated).async {
            input.startRunning()
        }
        hasStarted = true
    }

    private func clearPlaceholder() {
        view.subviews
            .filter { $0.accessibilityIdentifier == "CameraKitConfigurationPlaceholder" }
            .forEach { $0.removeFromSuperview() }
    }

    private func showConfigurationPlaceholder() {
        clearPlaceholder()

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .preferredFont(forTextStyle: .headline)
        label.textColor = .white
        label.text = """
        Camera Kit is installed.

        Add your Snap API token, Lens Group ID, and Lens ID in Info.plist or build settings.
        """

        let container = UIView()
        container.accessibilityIdentifier = "CameraKitConfigurationPlaceholder"
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = UIColor.black.withAlphaComponent(0.72)
        container.layer.cornerRadius = 18
        container.addSubview(label)
        view.addSubview(container)

        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            container.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            container.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            container.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -24),
        ])
    }
}

extension CameraKitViewController: LensRepositorySpecificObserver {
    func repository(_ repository: LensRepository, didUpdate lens: Lens, forGroupID groupID: String) {
        lensQueue.async { [weak self] in
            guard let self, appliedLensID == nil else {
                return
            }

            appliedLensID = lens.id
            cameraKit?.lenses.processor?.apply(lens: lens, launchData: nil) { success in
                if !success {
                    print("Camera Kit failed to apply lens \(lens.id)")
                }
            }
        }
    }

    func repository(_ repository: LensRepository, didFailToUpdateLensID lensID: String, forGroupID groupID: String, error: Error?) {
        if let error {
            print("Camera Kit failed to load lens \(lensID): \(error.localizedDescription)")
        }
    }
}
