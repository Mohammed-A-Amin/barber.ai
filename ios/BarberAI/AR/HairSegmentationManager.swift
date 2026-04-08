import ARKit
import CoreImage
import CoreVideo
import Foundation
import UIKit

#if canImport(MediaPipeTasksVision)
import MediaPipeTasksVision
#endif

final class HairSegmentationManager: NSObject {
    private let processingQueue = DispatchQueue(label: "ai.barber.hair-segmentation", qos: .userInitiated)
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let maskStateLock = NSLock()
    private var pixelBufferPool: CVPixelBufferPool?
    private var processedFrameCount = 0
    private var isEnabled = false
    private var isInferenceInFlight = false
    private var smoothedMaskValues: [Float] = []
    private var smoothedMaskSize = CGSize.zero

    // Blend raw mask frames over time to reduce flicker while keeping the
    // overlay responsive enough for head movement.
    private let temporalSmoothingFactor: Float = 0.35
    private let maskActivationThreshold: Float = 0.12
    private let maxOverlayAlpha: Float = 150.0

    #if canImport(MediaPipeTasksVision)
    private let modelName = "selfie_multiclass_256x256"
    private let hairCategoryIndex: UInt8 = 1

    private lazy var imageSegmenter: ImageSegmenter? = {
        do {
            guard let modelPath = Bundle.main.path(forResource: modelName, ofType: "tflite") else {
                onStatusChanged?("Segmentation model missing")
                return nil
            }

            let options = ImageSegmenterOptions()
            options.baseOptions.modelAssetPath = modelPath
            options.runningMode = .liveStream
            options.shouldOutputCategoryMask = true
            options.shouldOutputConfidenceMasks = false
            options.imageSegmenterLiveStreamDelegate = self

            let imageSegmenter = try ImageSegmenter(options: options)
            onStatusChanged?("Segmentation model ready")
            return imageSegmenter
        } catch {
            onStatusChanged?("Failed to load segmentation model")
            return nil
        }
    }()
    #endif

    var onMaskOverlayUpdated: ((UIImage?) -> Void)?
    var onStatusChanged: ((String) -> Void)?

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled

        if !enabled {
            resetStabilizationState()
            onMaskOverlayUpdated?(nil)
            onStatusChanged?("Hair mask disabled")
            return
        }

        if !isSegmenterAvailable {
            onStatusChanged?("MediaPipe unavailable")
            return
        }

        onStatusChanged?("Hair mask enabled")
    }

    func process(frame: ARFrame) {
        guard isEnabled, isSegmenterAvailable else {
            return
        }

        processedFrameCount += 1

        // Throttle segmentation to keep AR face tracking responsive.
        guard processedFrameCount % 3 == 0, !isInferenceInFlight else {
            return
        }

        let timestampInMilliseconds = Int(frame.timestamp * 1_000)
        let sourcePixelBuffer = frame.capturedImage

        processingQueue.async { [weak self] in
            guard let self else {
                return
            }

            guard let bgraPixelBuffer = self.makeBGRAPixelBuffer(from: sourcePixelBuffer) else {
                self.onStatusChanged?("Skipping frame: conversion failed")
                return
            }

            self.submitForSegmentation(pixelBuffer: bgraPixelBuffer, timestampInMilliseconds: timestampInMilliseconds)
        }
    }

    private func makeBGRAPixelBuffer(from source: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)

        if pixelBufferPool == nil {
            pixelBufferPool = makePixelBufferPool(width: width, height: height)
        }

        guard let pixelBufferPool else {
            return nil
        }

        var renderedBuffer: CVPixelBuffer?
        let creationStatus = CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool, &renderedBuffer)

        guard creationStatus == kCVReturnSuccess, let renderedBuffer else {
            return nil
        }

        let ciImage = CIImage(cvPixelBuffer: source)
        ciContext.render(ciImage, to: renderedBuffer)

        return renderedBuffer
    }

    private func makePixelBufferPool(width: Int, height: Int) -> CVPixelBufferPool? {
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferIOSurfacePropertiesKey: [:],
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]

        var pool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)

        guard status == kCVReturnSuccess else {
            return nil
        }

        return pool
    }

    private func resetStabilizationState() {
        maskStateLock.lock()
        defer { maskStateLock.unlock() }

        smoothedMaskValues.removeAll(keepingCapacity: false)
        smoothedMaskSize = .zero
    }

    private var isSegmenterAvailable: Bool {
        #if canImport(MediaPipeTasksVision)
        return imageSegmenter != nil
        #else
        return false
        #endif
    }

    private func submitForSegmentation(pixelBuffer: CVPixelBuffer, timestampInMilliseconds: Int) {
        #if canImport(MediaPipeTasksVision)
        guard let imageSegmenter else {
            return
        }

        do {
            let image = try MPImage(pixelBuffer: pixelBuffer)
            isInferenceInFlight = true
            try imageSegmenter.segmentAsync(image: image, timestampInMilliseconds: timestampInMilliseconds)
        } catch {
            isInferenceInFlight = false
            onStatusChanged?("Skipping frame: segmentation failed")
        }
        #endif
    }
}

#if canImport(MediaPipeTasksVision)
extension HairSegmentationManager: ImageSegmenterLiveStreamDelegate {
    func imageSegmenter(
        _ imageSegmenter: ImageSegmenter,
        didFinishSegmentation result: ImageSegmenterResult?,
        timestampInMilliseconds: Int,
        error: Error?
    ) {
        isInferenceInFlight = false

        if error != nil {
            onStatusChanged?("Segmentation error")
            return
        }

        guard let categoryMask = result?.categoryMask else {
            onStatusChanged?("Segmentation produced no mask")
            return
        }

        guard let overlayImage = makeOverlayImage(from: categoryMask) else {
            onStatusChanged?("Mask render failed")
            return
        }

        onMaskOverlayUpdated?(overlayImage)
        onStatusChanged?("Hair mask live")
    }

    private func makeOverlayImage(from mask: Mask) -> UIImage? {
        let width = mask.width
        let height = mask.height
        let pixelCount = width * height
        let categoryBytes = UnsafeBufferPointer(start: mask.uint8Data, count: pixelCount)
        var overlayBytes = [UInt8](repeating: 0, count: pixelCount * 4)

        maskStateLock.lock()

        if smoothedMaskSize.width != CGFloat(width) || smoothedMaskSize.height != CGFloat(height) {
            smoothedMaskValues = Array(repeating: 0, count: pixelCount)
            smoothedMaskSize = CGSize(width: width, height: height)
        } else if smoothedMaskValues.count != pixelCount {
            smoothedMaskValues = Array(repeating: 0, count: pixelCount)
        }

        for index in 0..<pixelCount {
            let currentValue: Float = categoryBytes[index] == hairCategoryIndex ? 1.0 : 0.0
            let previousValue = smoothedMaskValues[index]
            let smoothedValue = previousValue + (currentValue - previousValue) * temporalSmoothingFactor
            smoothedMaskValues[index] = smoothedValue

            guard smoothedValue > maskActivationThreshold else {
                continue
            }

            let normalizedAlpha = min(
                1.0,
                max(0.0, (smoothedValue - maskActivationThreshold) / (1.0 - maskActivationThreshold))
            )
            let pixelOffset = index * 4
            overlayBytes[pixelOffset] = 255
            overlayBytes[pixelOffset + 1] = 0
            overlayBytes[pixelOffset + 2] = 0
            overlayBytes[pixelOffset + 3] = UInt8(normalizedAlpha * maxOverlayAlpha)
        }

        maskStateLock.unlock()

        let bytesPerRow = width * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard
            let provider = CGDataProvider(data: Data(overlayBytes) as CFData),
            let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        else {
            return nil
        }

        // AR face tracking is portrait-only in this app and the front camera is
        // shown mirrored. MediaPipe's mask buffer comes back in the opposite
        // portrait rotation from ARKit's preview, so use the matching mirrored
        // orientation here to keep the overlay on the hairline instead of the chin.
        return UIImage(cgImage: cgImage, scale: 1.0, orientation: .rightMirrored)
    }
}
#endif
