import Foundation

/// Background listener that lets a previously-paired phone reconnect
/// without the user opening "Pair New Device" again. Owned by
/// AppDelegate; created at launch when `PairingStore` already has a
/// token + at least one paired phone.
///
/// What it does:
///   1. Opens a single RelayClient using the persisted Mac JWT.
///   2. Routes inbound `relay`-typed frames by their `from` peer.
///   3. For known paired phones, accepts a fresh Noise IK handshake
///      stage-1 frame and drives the responder side just like
///      PairingWindow does on first-time pair, except it never opens a
///      panel — the user doesn't need to know it's happening.
///   4. On Noise success, registers the resulting TakeoverSession with
///      a caller-supplied callback so AppDelegate can attach it to
///      whatever terminal session the active window has.
///   5. Encrypted-frame routing during transport: each phone's frames
///      go to the matching live TakeoverSession's RelayClient handler;
///      this coordinator is invisible once the session is active.
///
/// Limitation in this MVP: AppDelegate has at most one shared Mac
/// RelayClient. If the user opens PairingWindow while this listener is
/// running, PairingWindow's separate RelayClient (same token) will
/// transiently kick this one — the server's WSManager replaces an
/// older WS for the same deviceId. The listener auto-reconnects after
/// PairingWindow finishes / closes. A later P4-Hub slice will move
/// both behind a single shared RelayClient subscriber bus.
final class PairingCoordinator {
    private let serverURL: String
    private let macDeviceId: String
    private let macStaticKeyPair: NoiseKeyPair
    private var relay: RelayClient?
    /// In-progress responder per phone — keyed by phone deviceId. Once
    /// the handshake completes the entry is dropped and the
    /// TakeoverSession owns the routing.
    private var pendingResponders: [String: NoisePairResponder] = [:]
    /// `from -> TakeoverSession` so encrypted frames can be routed
    /// while the session is active. AppDelegate also keeps a mirror
    /// for lifecycle management — this map is the routing fast path.
    private var activeSessions: [String: TakeoverSession] = [:]
    /// Set of paired phone device ids we trust to initiate a reconnect.
    /// Refreshed on every restart from `PairingStore`.
    private var knownPhones: Set<String> = []

    /// Fired the moment a Noise handshake completes for a previously-
    /// paired phone, so AppDelegate can spin up a TakeoverSession bound
    /// to the active terminal. The coordinator hands off (relay ref,
    /// transport keys, phoneDeviceId, phoneName) — same shape as
    /// PairingWindow.PairingHandoff.
    var onReconnectCompleted: ((PairingHandoff) -> Void)?

    init(
        serverURL: String,
        macDeviceId: String,
        macStaticKeyPair: NoiseKeyPair
    ) {
        self.serverURL = serverURL
        self.macDeviceId = macDeviceId
        self.macStaticKeyPair = macStaticKeyPair
    }

    /// Boots the relay if we have a saved JWT + at least one paired
    /// phone. Idempotent — calling twice does nothing extra.
    func start() {
        guard relay == nil else { return }
        guard let token = PairingStore.loadMacToken() else {
            DebugLog.log("PairingCoordinator: no saved Mac token, skipping background listen")
            return
        }
        let phones = PairingStore.loadPairedPhones()
        guard !phones.isEmpty else {
            DebugLog.log("PairingCoordinator: no paired phones, skipping background listen")
            return
        }
        knownPhones = Set(phones.map(\.deviceId))

        let client = RelayClient(
            serverURL: serverURL,
            token: token,
            deviceId: macDeviceId,
            role: "mac"
        )
        client.onRelayFrame = { [weak self] from, payload in
            DispatchQueue.main.async { self?.route(from: from, payload: payload) }
        }
        client.onStateChange = { state in
            DebugLog.log("PairingCoordinator: relay state \(state)")
        }
        client.connect()
        relay = client
        DebugLog.log("PairingCoordinator: listening for \(phones.count) paired phone(s)")
    }

    /// Tear down — used on app quit and when the user "forgets" every
    /// paired phone (the listener has nothing to listen for).
    func stop() {
        for session in activeSessions.values { session.stop(reason: "coordinator_stop") }
        activeSessions.removeAll()
        pendingResponders.removeAll()
        relay?.disconnect()
        relay = nil
    }

    /// Removes a phone from the trust set + tears down any in-progress
    /// or active session for it. Called from a future "Forget this
    /// phone" UI; for now wired only to PairingStore.remove.
    func revoke(phoneDeviceId: String) {
        knownPhones.remove(phoneDeviceId)
        if let session = activeSessions.removeValue(forKey: phoneDeviceId) {
            session.stop(reason: "revoked")
        }
        pendingResponders.removeValue(forKey: phoneDeviceId)
        PairingStore.remove(deviceId: phoneDeviceId)
    }

    /// Inform the coordinator that a TakeoverSession started elsewhere
    /// (the first-time pair flow in PairingWindow) so future encrypted
    /// frames from that phone go to the right session. Called by
    /// AppDelegate from `startTakeover`.
    func registerActiveSession(_ session: TakeoverSession, for phoneDeviceId: String) {
        activeSessions[phoneDeviceId] = session
    }

    func unregisterActiveSession(for phoneDeviceId: String) {
        activeSessions.removeValue(forKey: phoneDeviceId)
    }

    // MARK: - Routing

    private func route(from: String, payload: [String: Any]) {
        guard knownPhones.contains(from) else {
            // A handshake from an unknown phone shouldn't be possible
            // (server only relays between paired tuples) but if
            // someone bypasses the pair gate this is the line of
            // defence. Log + drop.
            DebugLog.log("PairingCoordinator: dropping frame from unknown phone \(from)")
            return
        }
        guard let kind = payload["kind"] as? String else { return }
        switch kind {
        case "noise":
            handleNoiseFrame(from: from, payload: payload)
        case "encrypted":
            // If we already have a takeover session for this phone the
            // session installed its own onRelayFrame on a *different*
            // relay (the one PairingWindow handed off). Encrypted
            // frames arriving here mean either (a) the phone reconnected
            // to a fresh socket, in which case there's no live takeover
            // session yet, or (b) a stale frame after WS flap. Pre-
            // handshake encrypted frames are a protocol violation; drop
            // with a log so any drift is visible.
            DebugLog.log("PairingCoordinator: dropping encrypted frame from \(from) without a live session")
        default:
            break
        }
    }

    private func handleNoiseFrame(from: String, payload: [String: Any]) {
        guard let stage = payload["stage"] as? Int,
              let noisePayload = payload["noisePayload"] as? String else {
            DebugLog.log("PairingCoordinator: malformed noise frame from \(from)")
            return
        }
        let responder: NoisePairResponder
        if let existing = pendingResponders[from] {
            responder = existing
        } else {
            do {
                responder = try NoisePairResponder(
                    macStatic: macStaticKeyPair
                ) { [weak self] stageOut, b64 in
                    self?.relay?.sendRelay(to: from, payload: [
                        "kind": "noise",
                        "stage": stageOut,
                        "noisePayload": b64,
                    ])
                }
            } catch {
                DebugLog.log("PairingCoordinator: responder init failed: \(error)")
                return
            }
            pendingResponders[from] = responder
        }
        do {
            try responder.processIncomingFrame(.init(
                stage: stage,
                noisePayloadBase64: noisePayload
            ))
            if let result = responder.transportResult {
                pendingResponders.removeValue(forKey: from)
                completeReconnect(phoneDeviceId: from, transport: result)
            }
        } catch {
            DebugLog.log("PairingCoordinator: noise process failed: \(error)")
            pendingResponders.removeValue(forKey: from)
        }
    }

    private func completeReconnect(phoneDeviceId: String, transport: NoiseHandshakeState.Result) {
        guard let relay else { return }
        let phoneName = PairingStore.loadPairedPhones()
            .first(where: { $0.deviceId == phoneDeviceId })?.name ?? "phone"

        // Hand the warm relay off to AppDelegate so it can spin up the
        // TakeoverSession against the active terminal. The coordinator
        // still gets to register the session for routing — see
        // registerActiveSession.
        let handoff = PairingHandoff(
            relay: relay,
            phoneDeviceId: phoneDeviceId,
            phoneName: phoneName,
            transport: transport
        )
        // Drop our reference so AppDelegate's TakeoverSession can take
        // sole ownership of the relay (its `onRelayFrame` will be
        // re-installed by TakeoverSession.init).
        self.relay = nil
        DebugLog.log("PairingCoordinator: reconnect complete for \(phoneDeviceId)")
        onReconnectCompleted?(handoff)
    }
}
