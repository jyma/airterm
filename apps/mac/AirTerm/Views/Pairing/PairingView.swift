import SwiftUI
import CoreImage.CIFilterBuiltins

struct PairingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var remainingSeconds = 0
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: { dismiss() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("返回")
                    }
                    .foregroundStyle(.blue)
                    .font(.callout)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("配对新设备")
                    .font(.headline)

                Spacer()
                // Balance spacer
                Text("返回").opacity(0).font(.callout)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            Spacer()

            if let pairInfo = appState.pairInfo {
                // QR Code
                if let qrImage = generateQRCode(pairInfo: pairInfo) {
                    Image(nsImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 180, height: 180)
                        .padding(20)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                Text("用手机相机扫描二维码")
                    .font(.title3)
                    .fontWeight(.medium)
                    .padding(.top, 20)

                Text("自动打开 Web 控制台并完成配对\n无需注册账号")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)

                // Timer
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.caption)
                    Text("\(remainingSeconds / 60):\(String(format: "%02d", remainingSeconds % 60)) 后过期")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .padding(.top, 16)

                // Security badge
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text("端到端加密 · 设备本地验证")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 12)

            } else if appState.isPairing {
                ProgressView("正在生成配对码...")
            } else {
                Text("点击开始配对")
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .frame(width: 360, height: 480)
        .onAppear { startTimer() }
        .onDisappear { timer?.invalidate() }
        .onChange(of: appState.isPairing) { _, isPairing in
            if !isPairing { dismiss() }
        }
    }

    private func startTimer() {
        updateRemaining()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            updateRemaining()
        }
    }

    private func updateRemaining() {
        guard let pairInfo = appState.pairInfo else {
            remainingSeconds = 0
            return
        }
        remainingSeconds = max(0, pairInfo.expiresAt - Int(Date().timeIntervalSince1970))
        if remainingSeconds <= 0 {
            timer?.invalidate()
        }
    }

    private func generateQRCode(pairInfo: PairInfo) -> NSImage? {
        // Encode as URL so phone camera opens browser directly
        let baseURL = appState.serverURL
            .replacingOccurrences(of: "ws://", with: "http://")
            .replacingOccurrences(of: "wss://", with: "https://")
        let string = "\(baseURL)/pair?code=\(pairInfo.pairCode)"

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
