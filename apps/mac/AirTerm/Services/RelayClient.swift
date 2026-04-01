import Foundation

/// WebSocket client for connecting to the relay server.
/// Handles connection, authentication, message relay, and heartbeat.
final class RelayClient: NSObject, @unchecked Sendable, URLSessionWebSocketDelegate {
    enum State: Sendable {
        case disconnected
        case connecting
        case connected
    }

    private let serverURL: String
    private let token: String
    private let deviceId: String
    private let role: String

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var heartbeatTimer: Timer?
    private var reconnectAttempt = 0
    private let maxReconnectAttempts = 100
    private let reconnectDelays = [0.0, 1.0, 3.0, 10.0, 30.0]

    private(set) var state: State = .disconnected {
        didSet {
            if oldValue != state {
                onStateChange?(state)
            }
        }
    }

    var onMessage: (([String: Any]) -> Void)?
    var onStateChange: ((State) -> Void)?

    init(serverURL: String, token: String, deviceId: String, role: String = "mac") {
        self.serverURL = serverURL
        self.token = token
        self.deviceId = deviceId
        self.role = role
        super.init()
    }

    func connect() {
        guard state == .disconnected else { return }
        state = .connecting

        let wsURL = serverURL
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://", with: "ws://")
        let endpoint = "\(wsURL)/ws/\(role)?token=\(token)"

        guard let url = URL(string: endpoint) else {
            state = .disconnected
            return
        }

        let config = URLSessionConfiguration.default
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        webSocketTask = session?.webSocketTask(with: url)
        webSocketTask?.resume()
        receiveMessage()
    }

    func disconnect() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        session?.invalidateAndCancel()
        session = nil
        state = .disconnected
        reconnectAttempt = 0
    }

    func send(_ message: [String: Any]) {
        guard state == .connected else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let text = String(data: data, encoding: .utf8) else {
            return
        }
        webSocketTask?.send(.string(text)) { _ in }
    }

    /// Send a relay envelope to a target device
    func sendRelay(to targetId: String, payload: [String: Any]) {
        let envelope: [String: Any] = [
            "type": "relay",
            "from": deviceId,
            "to": targetId,
            "ts": Int(Date().timeIntervalSince1970 * 1000),
            "payload": encodePayload(payload),
        ]
        send(envelope)
    }

    // MARK: - URLSessionWebSocketDelegate

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        state = .connected
        reconnectAttempt = 0
        startHeartbeat()
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        state = .disconnected
        heartbeatTimer?.invalidate()
        scheduleReconnect()
    }

    // MARK: - Private

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    if let data = text.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        self?.handleMessage(json)
                    }
                case .data(let data):
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        self?.handleMessage(json)
                    }
                @unknown default:
                    break
                }
                self?.receiveMessage()

            case .failure:
                self?.state = .disconnected
                self?.scheduleReconnect()
            }
        }
    }

    private func handleMessage(_ json: [String: Any]) {
        if json["type"] as? String == "relay",
           let payload = json["payload"] as? String,
           let decoded = decodePayload(payload) {
            onMessage?(decoded)
        } else {
            onMessage?(json)
        }
    }

    private func startHeartbeat() {
        DispatchQueue.main.async { [weak self] in
            self?.heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                self?.send(["kind": "ping"])
            }
        }
    }

    private func scheduleReconnect() {
        guard reconnectAttempt < maxReconnectAttempts else { return }
        let delayIndex = min(reconnectAttempt, reconnectDelays.count - 1)
        let delay = reconnectDelays[delayIndex]
        reconnectAttempt += 1

        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.state = .disconnected
            self?.connect()
        }
    }

    private func encodePayload(_ payload: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return "" }
        return data.base64EncodedString()
    }

    private func decodePayload(_ base64: String) -> [String: Any]? {
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }
}
