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
    }

    /// Kicks off the pair-init network call, then renders the QR. Called
    /// from the menu action just before `makeKeyAndOrderFront(nil)`.
    func startPairing() {
        statusLabel.stringValue = "Requesting pair code…"
        Task { [weak self] in
            do {
                let info = try await self?.pairingService.initiatePairing()
                guard let self, let info else { return }
                let qr = self.pairingService.generateQRPayload(pairCode: info.pairCode)
                let json = (try? qr.encodedJSON()) ?? ""
                await MainActor.run { [weak self] in
                    self?.populateQR(json: json, pairCode: info.pairCode)
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.statusLabel.stringValue = "Failed: \(error.localizedDescription)"
                }
            }
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
