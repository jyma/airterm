import SwiftUI
import CoreImage.CIFilterBuiltins

struct PairingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Pair New Device")
                .font(.title2)
                .bold()

            if let pairInfo = appState.pairInfo {
                // Show QR code
                if let qrImage = generateQRCode(pairInfo: pairInfo) {
                    Image(nsImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200, height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // Show pair code
                Text(pairInfo.pairCode)
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .tracking(8)
                    .foregroundStyle(.primary)

                Text("Scan QR code or enter code on your phone")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Timer
                let remaining = max(0, pairInfo.expiresAt - Int(Date().timeIntervalSince1970))
                Text("Expires in \(remaining / 60):\(String(format: "%02d", remaining % 60))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView("Generating pair code...")
            }

            Button("Cancel") {
                appState.isPairing = false
                appState.pairInfo = nil
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding(30)
        .frame(width: 320)
    }

    private func generateQRCode(pairInfo: PairInfo) -> NSImage? {
        let payload = QRCodePayload(
            server: appState.serverURL,
            pairCode: pairInfo.pairCode,
            macDeviceId: appState.macDeviceId
        )

        guard let data = try? JSONEncoder().encode(payload) else { return nil }
        guard let string = String(data: data, encoding: .utf8) else { return nil }

        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let ciImage = filter.outputImage else { return nil }

        let scale = 10.0
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: scaled.extent.width, height: scaled.extent.height))
    }
}
