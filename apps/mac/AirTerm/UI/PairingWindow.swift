import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Modal-ish pairing panel. Opens via File → Pair New Device, calls the
/// relay server's /api/pair/init, then renders a v2 QR encoding the
/// {server, pairCode, macDeviceId, macPublicKey} JSON payload. The phone
/// scans this with the web app's QRScanner, POSTs /api/pair/complete,
/// and the server pushes a pair_completed notification on the Mac's WS
/// connection (wired in the next slice — for now the panel just shows
/// the QR and leaves a "Waiting for phone…" hint).
///
/// Why an NSPanel and not a sheet: the user might want to keep an eye
/// on the QR while looking at their phone — sheets attach to one
/// window and disappear on focus loss; NSPanel floats and stays put.
final class PairingWindow: NSPanel {
    private let pairingService: PairingService
    private let qrImageView = NSImageView()
    private let pairCodeLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let helperLabel = NSTextField(labelWithString: "")
    private let serverLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton(title: "Close", target: nil, action: nil)
    private var configToken: UUID?
    /// WS connection opened after /api/pair/init succeeds. Listens for the
    /// server's `pair_completed` notification and mutates the panel from
    /// "Waiting" → "Paired with <phone>!". Torn down on panel close so we
    /// don't leak connections per pair attempt.
    private var relay: RelayClient?
    /// Snapshot of the pair-init result so the WS-pair handler can format
    /// status messages without re-reading the panel's UI labels.
    private var lastPairInfo: PairInfo?
    /// Phone device id learned from the server's `pair_completed`
    /// notification. Used as the destination on every Noise / signaling
    /// frame the Mac sends back through the relay.
    private var phoneDeviceId: String?
    /// Friendly phone name from the same notification — kept around so
    /// the persisted PairedPhone record gets the right label even if the
    /// Noise handshake completes after the panel is dismissed.
    private var phoneName: String?
    /// IK responder driving the Noise handshake. Created the moment we
    /// learn there's a phone to talk to (`pair_completed` arrives or a
    /// stage-1 frame shows up first, whichever wins the race). nil after
    /// a successful handshake — transport CipherStates would live in a
    /// dedicated session manager once the takeover surface lands.
    private var noiseResponder: NoisePairResponder?
    /// Transport keys returned by the responder after stage 2. Held here
    /// so the panel can hand them off to whatever consumes the post-pair
    /// session (currently just persisted-marker; future: takeover
    /// surface).
    private var noiseResult: NoiseHandshakeState.Result?

    init(pairingService: PairingService) {
        self.pairingService = pairingService
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 480),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        title = "Pair New Device"
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false

        setupContent()
        applyTheme(ConfigStore.shared.theme)

        configToken = ConfigStore.shared.subscribe { [weak self] _, theme in
            self?.applyTheme(theme)
        }
    }

    deinit {
        if let token = configToken { ConfigStore.shared.unsubscribe(token) }
        // Tear down the WS via direct disconnect rather than `teardownRelay()`
        // so we don't touch UI labels (`lastPairInfo = nil` is intentional
        // there, but isn't necessary here since the panel is going away).
        relay?.disconnect()
        relay = nil
    }

    /// Kicks off the pair-init network call, renders the QR, and opens
    /// the WS connection that listens for the server's `pair_completed`
    /// notification. Called from the menu action just before
    /// `makeKeyAndOrderFront(nil)`.
    func startPairing() {
        // Re-entrant: closing & reopening the panel restarts pairing
        // cleanly, including any stale WS from a prior attempt.
        teardownRelay()
        statusLabel.stringValue = "Requesting pair code…"
        Task { [weak self] in
            do {
                let info = try await self?.pairingService.initiatePairing()
                guard let self, let info else { return }
                let qr = self.pairingService.generateQRPayload(pairCode: info.pairCode)
                let json = (try? qr.encodedJSON()) ?? ""
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.lastPairInfo = info
                    self.populateQR(json: json, pairCode: info.pairCode)
                    self.connectRelay(with: info.token)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.statusLabel.stringValue = "Failed: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Opens the WS to the relay using the JWT we just received and
    /// installs a handler that watches for the `pair_completed`
    /// notification. Connection state changes drive the visible status
    /// line so the user knows whether they're actually online.
    private func connectRelay(with token: String) {
        let client = RelayClient(
            serverURL: pairingService.relayServerURL,
            token: token,
            deviceId: pairingService.deviceId,
            role: "mac"
        )
        client.onMessage = { [weak self] message in
            DispatchQueue.main.async { self?.handleRelayMessage(message) }
        }
        client.onStateChange = { [weak self] state in
            DispatchQueue.main.async { self?.handleRelayState(state) }
        }
        relay = client
        client.connect()
    }

    private func teardownRelay() {
        relay?.disconnect()
        relay = nil
        lastPairInfo = nil
    }

    private func handleRelayState(_ state: RelayClient.State) {
        // Don't override the post-pair "Paired with X" message if we
        // happen to flap to disconnected after the notification arrived.
        if statusLabel.stringValue.hasPrefix("Paired with") { return }
        switch state {
        case .disconnected:
            statusLabel.stringValue = "Disconnected — retrying…"
        case .connecting:
            statusLabel.stringValue = "Opening relay channel…"
        case .connected:
            statusLabel.stringValue = "Waiting for phone…"
        }
    }

    private func handleRelayMessage(_ message: [String: Any]) {
        // Server-pushed pair_completed (no `kind`, has `type`) and signaling
        // frames forwarded from the phone (`kind: "noise"|"encrypted"`)
        // arrive on the same callback. Branch on shape.
        if let kind = message["kind"] as? String {
            handleSignalingMessage(kind: kind, body: message)
            return
        }
        guard let type = message["type"] as? String else { return }
        switch type {
        case "pair_completed":
            handlePairCompleted(message)
        default:
            break
        }
    }

    /// Server learned the phone scanned the QR + POSTed pair-complete.
    /// Now we have a phone deviceId/name to talk to and can lazy-create
    /// the Noise responder. We DON'T mark the pairing successful yet —
    /// "Paired" only after the Noise handshake succeeds, otherwise an
    /// MITM could land here without owning the responder static.
    private func handlePairCompleted(_ message: [String: Any]) {
        let pName = (message["phoneName"] as? String) ?? "phone"
        let pId   = (message["phoneDeviceId"] as? String) ?? ""
        self.phoneName = pName
        self.phoneDeviceId = pId.isEmpty ? nil : pId
        statusLabel.stringValue = "Securing channel with \(pName)…"
        // If a stage-1 Noise frame arrived BEFORE pair_completed (rare
        // race — the phone POSTs HTTP and connects WS in parallel), the
        // responder might already exist. Don't double-create.
        if noiseResponder == nil {
            ensureNoiseResponder()
        }
    }

    /// Routes signaling frames from the phone. Pre-handshake we expect
    /// only stage-1 Noise; post-handshake we'd expect EncryptedFrames
    /// (not yet wired — that's the takeover surface in a later phase).
    private func handleSignalingMessage(kind: String, body: [String: Any]) {
        switch kind {
        case "noise":
            ensureNoiseResponder()
            guard let responder = noiseResponder else { return }
            guard let stage = body["stage"] as? Int,
                  let payload = body["noisePayload"] as? String else {
                DebugLog.log("PairingWindow: malformed Noise frame")
                return
            }
            do {
                try responder.processIncomingFrame(.init(
                    stage: stage,
                    noisePayloadBase64: payload
                ))
                if let result = responder.transportResult {
                    noiseResult = result
                    finishPairing(handshakeHash: result.handshakeHash)
                }
            } catch {
                statusLabel.stringValue = "Pairing failed: \(error)"
            }
        case "encrypted":
            // Reserved for the takeover surface — phase 4+ will have
            // CipherStates handy here. For now we just log and drop.
            DebugLog.log("PairingWindow: dropping pre-takeover encrypted frame")
        default:
            break
        }
    }

    /// Lazy-creates the Noise IK responder using the Mac's static
    /// keypair. Idempotent — repeated calls (e.g. if a stage-1 frame
    /// races pair_completed) return early. The `sendFrame` callback
    /// wraps stage-2 in a SignalingMessage and posts it through the
    /// relay's sequenced-message envelope.
    private func ensureNoiseResponder() {
        guard noiseResponder == nil else { return }
        do {
            let responder = try NoisePairResponder(
                macStatic: pairingService.staticNoiseKeyPair
            ) { [weak self] stage, noisePayloadBase64 in
                self?.sendNoiseFrame(stage: stage, noisePayloadBase64: noisePayloadBase64)
            }
            noiseResponder = responder
        } catch {
            DebugLog.log("PairingWindow: Noise responder init failed: \(error)")
            statusLabel.stringValue = "Pairing failed to start: \(error)"
        }
    }

    private func sendNoiseFrame(stage: Int, noisePayloadBase64: String) {
        guard let phoneDeviceId else {
            DebugLog.log("PairingWindow: tried to send Noise frame before knowing phone deviceId")
            return
        }
        relay?.sendRelay(to: phoneDeviceId, payload: [
            "kind": "noise",
            "stage": stage,
            "noisePayload": noisePayloadBase64,
        ])
    }

    /// Final success path. Persists the paired phone (now we have its
    /// long-lived static public key, which the responder learned during
    /// stage 1) and updates the panel.
    private func finishPairing(handshakeHash: Data) {
        let nameForUI = phoneName ?? "phone"
        statusLabel.stringValue = "Securely paired with \(nameForUI)!"
        helperLabel.stringValue = "Channel binding: \(handshakeHash.prefix(4).map { String(format: "%02x", $0) }.joined())…"
        closeButton.title = "Done"
        if let phoneDeviceId, let phonePublicKey = noiseResponder?.learnedInitiatorStaticPublicKey {
            PairingStore.addOrUpdate(PairedPhone(
                deviceId: phoneDeviceId,
                name: nameForUI,
                pairedAt: Date(),
                publicKey: phonePublicKey.base64EncodedString()
            ))
        }
        if let token = lastPairInfo?.token {
            PairingStore.saveMacToken(token)
        }
    }

    // MARK: - Layout

    private func setupContent() {
        guard let content = contentView else { return }
        content.wantsLayer = true

        // QR centred near the top.
        qrImageView.frame = NSRect(x: 50, y: 200, width: 280, height: 280)
        qrImageView.imageScaling = .scaleProportionallyUpOrDown
        qrImageView.wantsLayer = true
        qrImageView.layer?.cornerRadius = 12
        qrImageView.layer?.masksToBounds = true
        content.addSubview(qrImageView)

        pairCodeLabel.frame = NSRect(x: 20, y: 152, width: 340, height: 36)
        pairCodeLabel.alignment = .center
        pairCodeLabel.font = NSFont.monospacedSystemFont(ofSize: 28, weight: .bold)
        pairCodeLabel.stringValue = "------"
        content.addSubview(pairCodeLabel)

        helperLabel.frame = NSRect(x: 20, y: 124, width: 340, height: 20)
        helperLabel.alignment = .center
        helperLabel.font = NSFont.systemFont(ofSize: 12)
        helperLabel.textColor = .secondaryLabelColor
        helperLabel.stringValue = "Pair code (enter manually if scanning fails)"
        content.addSubview(helperLabel)

        statusLabel.frame = NSRect(x: 20, y: 84, width: 340, height: 28)
        statusLabel.alignment = .center
        statusLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        statusLabel.stringValue = ""
        content.addSubview(statusLabel)

        serverLabel.frame = NSRect(x: 20, y: 60, width: 340, height: 16)
        serverLabel.alignment = .center
        serverLabel.font = NSFont.systemFont(ofSize: 10)
        serverLabel.textColor = .tertiaryLabelColor
        serverLabel.stringValue = ""
        content.addSubview(serverLabel)

        closeButton.frame = NSRect(x: 140, y: 18, width: 100, height: 28)
        closeButton.bezelStyle = .rounded
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.keyEquivalent = "\u{1B}"  // Esc
        content.addSubview(closeButton)
    }

    private func applyTheme(_ theme: Theme) {
        guard let content = contentView else { return }
        let bg = theme.background
        content.layer?.backgroundColor = CGColor(
            srgbRed: CGFloat(bg.x), green: CGFloat(bg.y),
            blue: CGFloat(bg.z), alpha: 1
        )
        let fg = theme.foreground
        let accent = theme.accent
        pairCodeLabel.textColor = NSColor(
            srgbRed: CGFloat(accent.x), green: CGFloat(accent.y),
            blue: CGFloat(accent.z), alpha: 1
        )
        statusLabel.textColor = NSColor(
            srgbRed: CGFloat(fg.x), green: CGFloat(fg.y),
            blue: CGFloat(fg.z), alpha: 0.85
        )
    }

    private func populateQR(json: String, pairCode: String) {
        pairCodeLabel.stringValue = pairCode
        statusLabel.stringValue = "Waiting for phone…"
        serverLabel.stringValue = "Scan or enter the code on the AirTerm web app"
        if let img = Self.makeQRImage(payload: json, sizePoints: 280) {
            qrImageView.image = img
        } else {
            statusLabel.stringValue = "QR rendering failed — use the pair code instead"
        }
    }

    @objc private func closeClicked() {
        teardownRelay()
        orderOut(nil)
    }

    // MARK: - QR Code generation

    /// Renders the JSON payload as a high-error-correction QR code, scaled
    /// to roughly `sizePoints` × `sizePoints` points so it looks crisp on
    /// retina displays.
    static func makeQRImage(payload: String, sizePoints: CGFloat) -> NSImage? {
        guard let data = payload.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        // 'H' = ~30% recovery — comfortably tolerates a centred logo or
        // print artefacts and still scans on phones in dim light.
        filter.correctionLevel = "H"
        guard let raw = filter.outputImage else { return nil }
        let scale = sizePoints / raw.extent.width
        let scaled = raw.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let rep = NSCIImageRep(ciImage: scaled)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)
        return nsImage
    }
}
