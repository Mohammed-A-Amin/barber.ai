import SwiftUI

struct ARAssistantOverlayView: View {
    private let context: BarberAIAPI.StyleContext

    @StateObject private var voiceSession: RealtimeVoiceSession
    @State private var messageText = ""
    @State private var messages: [StyleChatMessage] = [
        StyleChatMessage(role: .assistant, text: "Ask if this hairstyle fits you, or tap the mic for live voice advice."),
    ]
    @State private var isSending = false

    init(context: BarberAIAPI.StyleContext) {
        self.context = context
        _voiceSession = StateObject(
            wrappedValue: RealtimeVoiceSession(contextProvider: { context })
        )
    }

    var body: some View {
        VStack {
            Spacer()

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Label("Style Assistant", systemImage: "sparkles")
                        .font(.headline)

                    Spacer()

                    Button {
                        Task { @MainActor in
                            voiceSession.toggle()
                        }
                    } label: {
                        Image(systemName: voiceButtonImageName)
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 38, height: 38)
                            .foregroundStyle(.white)
                            .background(voiceButtonColor, in: Circle())
                    }
                    .accessibilityLabel("Toggle realtime voice chat")
                }

                Text(voiceStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(messages) { message in
                                Text(message.text)
                                    .font(.subheadline)
                                    .foregroundStyle(message.role == .user ? .white : .primary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 9)
                                    .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
                                    .background(message.role == .user ? Color.accentColor : Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 14))
                                    .id(message.id)
                            }
                        }
                    }
                    .frame(maxHeight: 190)
                    .onChange(of: messages.count) { _ in
                        if let lastMessageID = messages.last?.id {
                            withAnimation(.snappy) {
                                proxy.scrollTo(lastMessageID, anchor: .bottom)
                            }
                        }
                    }
                }

                HStack(spacing: 10) {
                    TextField("Ask about this style", text: $messageText, axis: .vertical)
                        .lineLimit(1...3)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 16))

                    Button {
                        Task {
                            await sendMessage()
                        }
                    } label: {
                        if isSending {
                            ProgressView()
                                .tint(.white)
                                .frame(width: 40, height: 40)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                        }
                    }
                    .background(Color.accentColor, in: Circle())
                    .disabled(isSending || messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Send style question")
                }
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
            .padding(.horizontal, 14)
            .padding(.bottom, 88)
        }
    }

    private var voiceButtonImageName: String {
        switch voiceSession.connectionState {
        case .connected:
            return "phone.down.fill"
        case .connecting:
            return "waveform"
        case .idle, .failed:
            return "mic.fill"
        }
    }

    private var voiceButtonColor: Color {
        switch voiceSession.connectionState {
        case .connected:
            return .red
        case .connecting:
            return .orange
        case .idle:
            return .black
        case .failed:
            return .red.opacity(0.85)
        }
    }

    private var voiceStatusText: String {
        switch voiceSession.connectionState {
        case .idle:
            return "Text sends one screenshot. Voice uses realtime audio and the current AR frame."
        case .connecting:
            return "Connecting realtime voice..."
        case .connected:
            return "Realtime voice is active. Tap the red button to stop."
        case .failed(let error):
            return "Voice failed: \(error)"
        }
    }

    @MainActor
    private func sendMessage() async {
        let trimmedMessage = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty, !isSending else {
            return
        }

        messageText = ""
        isSending = true
        messages.append(StyleChatMessage(role: .user, text: trimmedMessage))

        do {
            let screenshot = ARViewSnapshotter.captureJPEGData()
            let response = try await BarberAIAPI.shared.styleAdvice(
                message: trimmedMessage,
                imageJPEGData: screenshot,
                context: context
            )
            messages.append(StyleChatMessage(role: .assistant, text: response))
        } catch {
            messages.append(StyleChatMessage(role: .assistant, text: error.localizedDescription))
        }

        isSending = false
    }
}

private struct StyleChatMessage: Identifiable {
    enum Role {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    let text: String
}

struct ARAssistantOverlayView_Previews: PreviewProvider {
    static var previews: some View {
        ARAssistantOverlayView(context: BarberAIAPI.StyleContext(activeLensId: "preview", activeStyle: "Hair Example", hairColor: "#5A3825"))
            .background(Color.gray)
    }
}
