import AVFoundation
import Foundation
import WebRTC

final class RealtimeVoiceSession: NSObject, ObservableObject {
    enum ConnectionState: Equatable {
        case idle
        case connecting
        case connected
        case failed(String)
    }

    @Published private(set) var connectionState: ConnectionState = .idle

    private let api: BarberAIAPI
    private let contextProvider: () -> BarberAIAPI.StyleContext
    private let factory: RTCPeerConnectionFactory
    private var peerConnection: RTCPeerConnection?
    private var dataChannel: RTCDataChannel?
    private var pendingContextImage: String?

    init(
        api: BarberAIAPI = .shared,
        contextProvider: @escaping () -> BarberAIAPI.StyleContext = { BarberAIAPI.StyleContext() }
    ) {
        self.api = api
        self.contextProvider = contextProvider
        RTCInitializeSSL()
        self.factory = RTCPeerConnectionFactory()
        super.init()
    }

    @MainActor
    func toggle() {
        switch connectionState {
        case .idle, .failed:
            Task {
                await start()
            }
        case .connecting, .connected:
            stop()
        }
    }

    @MainActor
    func start() async {
        guard connectionState != .connecting && connectionState != .connected else {
            return
        }

        connectionState = .connecting

        do {
            try configureAudioSession()
            let context = contextProvider()
            let screenshotData = ARViewSnapshotter.captureJPEGData()
            pendingContextImage = screenshotData?.base64EncodedString()

            let peerConnection = makePeerConnection()
            self.peerConnection = peerConnection

            let audioTrack = factory.audioTrack(withTrackId: "barber-ai-mic")
            peerConnection.add(audioTrack, streamIds: ["barber-ai-audio"])

            let dataChannelConfig = RTCDataChannelConfiguration()
            let dataChannel = peerConnection.dataChannel(forLabel: "oai-events", configuration: dataChannelConfig)
            self.dataChannel = dataChannel
            dataChannel?.delegate = self

            let offer = try await makeOffer(peerConnection: peerConnection)
            try await setLocalDescription(offer, peerConnection: peerConnection)
            let answerSDP = try await api.realtimeAnswerSDP(
                localSDP: offer.sdp,
                imageJPEGData: screenshotData,
                context: context
            )
            let answer = RTCSessionDescription(type: .answer, sdp: answerSDP)
            try await setRemoteDescription(answer, peerConnection: peerConnection)
        } catch {
            stop()
            connectionState = .failed(error.localizedDescription)
        }
    }

    @MainActor
    func stop() {
        dataChannel?.close()
        dataChannel = nil
        peerConnection?.close()
        peerConnection = nil
        pendingContextImage = nil
        connectionState = .idle
    }

    private func makePeerConnection() -> RTCPeerConnection {
        let configuration = RTCConfiguration()
        configuration.sdpSemantics = .unifiedPlan

        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let peerConnection = factory.peerConnection(
            with: configuration,
            constraints: constraints,
            delegate: self
        )

        return peerConnection
    }

    private func configureAudioSession() throws {
        let session = RTCAudioSession.sharedInstance()
        session.lockForConfiguration()
        defer {
            session.unlockForConfiguration()
        }

        try session.setCategory(
            AVAudioSession.Category.playAndRecord.rawValue,
            with: [.allowBluetooth, .defaultToSpeaker]
        )
        try session.setMode(AVAudioSession.Mode.voiceChat.rawValue)
        try session.setActive(true)
    }

    private func makeOffer(peerConnection: RTCPeerConnection) async throws -> RTCSessionDescription {
        try await withCheckedThrowingContinuation { continuation in
            let constraints = RTCMediaConstraints(
                mandatoryConstraints: [
                    "OfferToReceiveAudio": "true",
                ],
                optionalConstraints: nil
            )

            peerConnection.offer(for: constraints) { description, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let description else {
                    continuation.resume(throwing: BarberAIAPI.APIError.invalidResponse)
                    return
                }

                continuation.resume(returning: description)
            }
        }
    }

    private func setLocalDescription(
        _ description: RTCSessionDescription,
        peerConnection: RTCPeerConnection
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peerConnection.setLocalDescription(description) { error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume()
            }
        }
    }

    private func setRemoteDescription(
        _ description: RTCSessionDescription,
        peerConnection: RTCPeerConnection
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peerConnection.setRemoteDescription(description) { error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                continuation.resume()
            }
        }
    }

    private func sendInitialImageContextIfPossible() {
        guard
            let pendingContextImage,
            let dataChannel,
            dataChannel.readyState == .open
        else {
            return
        }

        let event: [String: Any] = [
            "type": "conversation.item.create",
            "item": [
                "type": "message",
                "role": "user",
                "content": [
                    [
                        "type": "input_text",
                        "text": "Use this current AR try-on screenshot as visual context for hairstyle advice during this voice conversation.",
                    ],
                    [
                        "type": "input_image",
                        "image_url": "data:image/jpeg;base64,\(pendingContextImage)",
                    ],
                ],
            ],
        ]

        guard
            let data = try? JSONSerialization.data(withJSONObject: event),
            let json = String(data: data, encoding: .utf8)
        else {
            return
        }

        dataChannel.sendData(RTCDataBuffer(data: Data(json.utf8), isBinary: false))
        self.pendingContextImage = nil
    }
}

extension RealtimeVoiceSession: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        DispatchQueue.main.async { [weak self] in
            switch newState {
            case .connected, .completed:
                self?.connectionState = .connected
            case .failed, .disconnected, .closed:
                self?.connectionState = .failed("Realtime voice disconnected.")
            default:
                break
            }
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        dataChannel.delegate = self
        self.dataChannel = dataChannel
        sendInitialImageContextIfPossible()
    }
}

extension RealtimeVoiceSession: RTCDataChannelDelegate {
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        if dataChannel.readyState == .open {
            sendInitialImageContextIfPossible()
        }
    }

    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {}
}
