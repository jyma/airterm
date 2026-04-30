import Foundation

/// Long-lived broadcast session that pumps `TerminalSession` state to a
/// paired phone over the post-handshake Noise transport, and applies
/// inbound `InputEvent` / `Resize` frames back to the same shell.
///
/// Lifecycle: created by AppDelegate when the PairingWindow finishes
/// the Noise IK handshake. Owns the RelayClient that PairingWindow
/// opened (so the WS keeps running after the user dismisses the panel)
/// and the bridge to the active TerminalSession. Stops when:
///   • the phone sends a `bye` frame
///   • the WS disconnects and won't reconnect
///   • the caller invokes `stop()`
///
/// Cadence: 30Hz timer takes a TerminalScreen snapshot, asks the
/// TakeoverEncoder for a frame (snapshot or delta), and ships it
/// through the TakeoverChannel. Idle ticks where no row changed
/// produce no frame, so a quiet shell costs nothing.
final class TakeoverSession {
    private let relay: RelayClient
    private let phoneDeviceId: String
    private let terminalSession: TerminalSession
    private let channel: TakeoverChannel
    private var encoder: TakeoverEncoder
    private var timer: Timer?
    private(set) var isRunning: Bool = false
    private var configToken: UUID?

    /// Frame rate for the screen-broadcast loop. Phase 4 MVP keeps it
    /// modest; later phases will move to event-driven (push on
    /// TerminalScreen.didUpdate) for lower latency + zero idle cost.
    static let frameHz: Double = 30

    /// Caller observer fired whenever the WS state changes — surfaces
    /// "Disconnected" / "Reconnecting" / "Online" so the Mac UI can
    /// show a takeover-status indicator.
    var onStateChange: ((RelayClient.State) -> Void)?

    /// Caller observer fired when the phone sends a `bye` or the WS
    /// goes down terminally — UI uses it to mark this phone offline.
    var onEnded: ((String?) -> Void)?

    init(
        relay: RelayClient,
        phoneDeviceId: String,
        terminalSession: TerminalSession,
        transport: NoiseHandshakeState.Result,
        theme: Theme = ConfigStore.shared.theme
    ) {
        self.relay = relay
        self.phoneDeviceId = phoneDeviceId
        self.terminalSession = terminalSession
        self.encoder = TakeoverEncoder(theme: theme)

        // sendSignaling captures `relay` and `phoneDeviceId` so the
        // channel doesn't need to know either. We send the encrypted-
        // frame dict straight through `RelayClient.sendRelay`, which
        // wraps it in a SequencedMessage + RelayEnvelope before WS-
        // serializing.
        let phoneId = phoneDeviceId
        let r = relay
        self.channel = TakeoverChannel(
            send: transport.send,
            receive: transport.receive,
            sendSignaling: { dict in r.sendRelay(to: phoneId, payload: dict) },
            onFrame: { _ in /* installed after init below */ },
            onError: { err in
                DebugLog.log("TakeoverSession: channel error: \(err)")
            }
        )

        // Install the [weak self] inbound handler now that the channel
        // exists. The mutable `onFrame` lets us avoid a circular init.
        self.channel.onFrame = { [weak self] frame in
            self?.handle(inboundFrame: frame)
        }

        // The relay's onMessage already routes pair_completed +
        // signaling to PairingWindow. Now that takeover is live, the
        // phone's encrypted frames must reach US. We swap in our own
        // handler — PairingWindow has already detached.
        relay.onMessage = { [weak self] message in
            DispatchQueue.main.async { self?.handle(relayMessage: message) }
        }
        relay.onStateChange = { [weak self] state in
            DispatchQueue.main.async { self?.onStateChange?(state) }
        }

        // Theme changes re-tint every cell. Force a full snapshot the
        // next frame so the phone sees them without waiting for cell
        // content changes to drag colours in row-by-row.
        configToken = ConfigStore.shared.subscribe { [weak self] _, theme in
            self?.encoder.updateTheme(theme)
        }
    }

    deinit {
        if let token = configToken { ConfigStore.shared.unsubscribe(token) }
        stop()
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        let interval = 1.0 / Self.frameHz
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // Force the first tick right away so the phone sees a frame
        // before the next 33ms cycle.
        DispatchQueue.main.async { [weak self] in self?.tick() }
    }

    func stop(reason: String? = nil) {
        guard isRunning else {
            relay.disconnect()
            return
        }
        isRunning = false
        timer?.invalidate()
        timer = nil
        // Best-effort bye; if the channel's already torn down this is a no-op.
        try? channel.sendFrame(.bye(TakeoverByeFrame(seq: -1, reason: reason)))
        channel.close()
        relay.disconnect()
        onEnded?(reason)
    }

    // MARK: - Outbound

    private func tick() {
        guard isRunning else { return }
        let snapshot = terminalSession.snapshot()
        guard let frame = encoder.frame(for: snapshot) else { return }
        do {
            try channel.sendFrame(frame)
        } catch {
            DebugLog.log("TakeoverSession: outbound encode failed: \(error)")
            stop(reason: "channel_error")
        }
    }

    // MARK: - Inbound

    private func handle(relayMessage: [String: Any]) {
        // The relay's onMessage delivers the inner SignalingMessage
        // dict (already unwrapped from RelayEnvelope + SequencedMessage).
        // TakeoverChannel only owns `kind: "encrypted"`; everything
        // else (re-delivered pair_completed, late noise frames) we
        // ignore here since pairing is done.
        channel.handleIncoming(relayMessage)
    }

    private func handle(inboundFrame: TakeoverFrame) {
        switch inboundFrame {
        case .inputEvent(let evt):
            guard let bytes = Data(base64Encoded: evt.bytes) else {
                DebugLog.log("TakeoverSession: input bytes not base64")
                return
            }
            terminalSession.send(bytes)
        case .resize(let rs):
            // Mac PTY resize uses UInt16; clamp negative / overflow.
            let safeRows = UInt16(max(1, min(Int(UInt16.max), rs.rows)))
            let safeCols = UInt16(max(1, min(Int(UInt16.max), rs.cols)))
            terminalSession.resize(rows: safeRows, cols: safeCols)
            // Resize invalidates the diff baseline — next frame must
            // be a full snapshot at the new geometry.
            encoder.resetForReconnect()
        case .ping:
            // Phone keep-alive. Phase 4.x will respond with a pong;
            // for now the WS heartbeat covers liveness.
            break
        case .bye(let bye):
            stop(reason: bye.reason ?? "phone_bye")
        case .screenSnapshot, .screenDelta:
            // Mac is the screen sender, not receiver. Inbound screens
            // are a protocol violation; drop them.
            DebugLog.log("TakeoverSession: dropping inbound screen frame")
        }
    }
}

