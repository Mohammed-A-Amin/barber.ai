import UIKit

enum ARViewSnapshotter {
    @MainActor
    static func captureJPEGData(quality: CGFloat = 0.62) -> Data? {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        else {
            return nil
        }

        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }

        return image.jpegData(compressionQuality: quality)
    }
}
