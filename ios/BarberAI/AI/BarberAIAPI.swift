import Foundation

struct BarberAIAPI {
    enum APIError: LocalizedError {
        case missingBaseURL
        case invalidResponse
        case serverError

        var errorDescription: String? {
            switch self {
            case .missingBaseURL:
                return "Set BARBER_AI_API_BASE_URL in your xcconfig."
            case .invalidResponse:
                return "The server returned an invalid response."
            case .serverError:
                return "The AI server could not answer right now."
            }
        }
    }

    struct StyleAdviceResponse: Decodable {
        let message: String
    }

    struct StyleContext: Codable {
        var activeLensId: String?
        var activeStyle: String?
        var hairColor: String?
    }

    static var shared: BarberAIAPI {
        BarberAIAPI(baseURL: Bundle.main.barberAIAPIBaseURL)
    }

    let baseURL: URL?

    func styleAdvice(message: String, imageJPEGData: Data?, context: StyleContext) async throws -> String {
        guard let baseURL else {
            throw APIError.missingBaseURL
        }

        var request = URLRequest(url: baseURL.appending(path: "ai/style-advice"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(StyleAdviceRequest(
            message: message,
            imageBase64: imageJPEGData?.base64EncodedString(),
            activeLensId: context.activeLensId,
            activeStyle: context.activeStyle,
            hairColor: context.hairColor
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw APIError.serverError
        }

        return try JSONDecoder().decode(StyleAdviceResponse.self, from: data).message
    }

    func realtimeAnswerSDP(localSDP: String, imageJPEGData: Data?, context: StyleContext) async throws -> String {
        guard let baseURL else {
            throw APIError.missingBaseURL
        }

        var request = URLRequest(url: baseURL.appending(path: "ai/realtime/sdp"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(RealtimeSDPRequest(
            sdp: localSDP,
            imageBase64: imageJPEGData?.base64EncodedString(),
            activeLensId: context.activeLensId,
            activeStyle: context.activeStyle,
            hairColor: context.hairColor
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode), let sdp = String(data: data, encoding: .utf8) else {
            throw APIError.serverError
        }

        return sdp
    }
}

private struct StyleAdviceRequest: Encodable {
    let message: String
    let imageBase64: String?
    let activeLensId: String?
    let activeStyle: String?
    let hairColor: String?
}

private struct RealtimeSDPRequest: Encodable {
    let sdp: String
    let imageBase64: String?
    let activeLensId: String?
    let activeStyle: String?
    let hairColor: String?
}

private extension Bundle {
    var barberAIAPIBaseURL: URL? {
        guard
            let rawValue = object(forInfoDictionaryKey: "BarberAIAPIBaseURL") as? String
        else {
            return nil
        }

        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty, !trimmedValue.contains("$(") else {
            return nil
        }

        return URL(string: trimmedValue)
    }
}
