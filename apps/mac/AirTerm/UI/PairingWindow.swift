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
        guard let type = message["type"] as? String else { return }
        switch type {
        case "pair_completed":
            let phoneName = (message["phoneName"] as? String) ?? "phone"
            statusLabel.stringValue = "Paired with \(phoneName)!"
            helperLabel.stringValue = "You can close this panel."
            closeButton.title = "Done"
        default:
            break
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
