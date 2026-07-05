import Foundation

/// Direct client for Runway's developer API (api.dev.runwayml.com). Task-based: POST a generation
/// task, then poll GET /v1/tasks/{id} until SUCCEEDED and return the output URLs. Field names and
/// enums verified against Runway's official SDK (runwayml/sdk-node).
actor RunwayClient {
    let apiKey: String

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    private static let base = "https://api.dev.runwayml.com/v1"
    private static let versionHeader = "2024-11-06"
    private static let pollInterval: UInt64 = 3_000_000_000 // 3s
    private static let maxWait: TimeInterval = 10 * 60

    // MARK: - Generation

    /// POST /v1/image_to_video — promptImage is REQUIRED for every Runway video model.
    func imageToVideo(
        model: String, promptImage: String, promptText: String, ratio: String, duration: Int
    ) async throws -> [String] {
        let taskId = try await createTask(path: "image_to_video", body: [
            "model": model,
            "promptImage": promptImage,
            "promptText": promptText,
            "ratio": ratio,
            "duration": duration,
        ])
        return try await waitForOutput(taskId: taskId)
    }

    /// POST /v1/text_to_image.
    func textToImage(model: String, promptText: String, ratio: String) async throws -> [String] {
        let taskId = try await createTask(path: "text_to_image", body: [
            "model": model,
            "promptText": promptText,
            "ratio": ratio,
        ])
        return try await waitForOutput(taskId: taskId)
    }

    // MARK: - Task flow

    private func createTask(path: String, body: [String: Any]) async throws -> String {
        let (data, status) = try await send(method: "POST", path: path, body: body)
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard (200..<300).contains(status), let id = json?["id"] as? String else {
            let detail = String(data: data.prefix(500), encoding: .utf8) ?? ""
            throw GenerationBackendError.transport("Runway HTTP \(status): \(detail)")
        }
        return id
    }

    private func waitForOutput(taskId: String) async throws -> [String] {
        let deadline = Date().addingTimeInterval(Self.maxWait)
        while true {
            let (data, status) = try await send(method: "GET", path: "tasks/\(taskId)", body: nil)
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard (200..<300).contains(status), let state = json?["status"] as? String else {
                let detail = String(data: data.prefix(300), encoding: .utf8) ?? ""
                throw GenerationBackendError.transport("Runway task poll HTTP \(status): \(detail)")
            }
            switch state {
            case "SUCCEEDED":
                guard let output = json?["output"] as? [String], !output.isEmpty else {
                    throw GenerationBackendError.transport("Runway returned no output")
                }
                return output
            case "FAILED", "CANCELLED":
                let reason = (json?["failure"] as? String) ?? "Runway generation \(state.lowercased())"
                throw GenerationBackendError.transport(reason)
            default: // PENDING, THROTTLED, RUNNING
                if Date() >= deadline {
                    throw GenerationBackendError.transport("Runway generation timed out")
                }
                try await Task.sleep(nanoseconds: Self.pollInterval)
            }
        }
    }

    private func send(method: String, path: String, body: [String: Any]?) async throws -> (Data, Int) {
        guard let url = URL(string: "\(Self.base)/\(path)") else {
            throw GenerationBackendError.transport("Invalid Runway endpoint: \(path)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.versionHeader, forHTTPHeaderField: "X-Runway-Version")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}
