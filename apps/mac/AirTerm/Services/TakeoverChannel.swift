import Foundation

/// Mac mirror of `apps/web/src/lib/takeover-channel.ts`. Wraps two
/// post-handshake `NoiseCipherState`s — one outbound, one inbound —
/// and maps `TakeoverFrame`s onto the on-wire `EncryptedFrame` shape
/// the WS relay carries.
///
/// Wire stack per outbound frame:
///   TakeoverFrame
///     ↓ TakeoverFrameCodec.encode  (JSON, UTF-8)
///   plaintext bytes
///     ↓ NoiseCipherState.encrypt   (ChaCha20-Poly1305 + counter nonce)
///   ciphertext bytes
///     ↓ base64
///   {kind: "encrypted", seq, ciphertext}
///     ↓ caller wraps in SequencedMessage + RelayEnvelope (RelayClient)
///
/// Inbound is the inverse, with replay rejection on `lastIncomingSeq`
/// so a relay-replayed frame is dropped before the AEAD even runs.
///
/// All UI-visible frames go through `onFrame`; non-fatal failures
/// (decode, AEAD, replay) report via `onError` so the channel survives
/// a single bad frame and the caller can surface telemetry.
final class TakeoverChannel {
    enum ChannelError: Error, CustomStringConvertible {
        case closed
        case replay(seq: Int, expected: Int)
        case aeadFailure(String)
        case decodeFailure(String)
        case malformed(String)

        var description: String {
            switch self {
            case .closed: return "TakeoverChannel is closed"
            case .replay(let s, let e):
                return "replayed/out-of-order frame seq=\(s) expected > \(e)"
            case .aeadFailure(let s): return "aead failure: \(s)"
            case .decodeFailure(let s): return "decode failure: \(s)"
            case .malformed(let s): return "malformed signaling: \(s)"
            }
        }
    }

    private let send: NoiseCipherState
    private let receive: NoiseCipherState
    private let sendSignaling: (_ encryptedFrame: [String: Any]) -> Void
    /// Mutable so a long-lived owner (TakeoverSession) can install a
    /// `[weak self]` handler after construction without a fragile
    /// init-order dance.
    var onFrame: (TakeoverFrame) -> Void
    var onError: (ChannelError) -> Void
    private var outboundSeq = 0
    private var lastIncomingSeq = -1
    private(set) var isClosed = false

    /// Caller wires `sendSignaling` into whatever channel it has open
    /// (typically `RelayClient.sendRelay(to:payload:)` with the dict
    /// passed straight through). The encrypted-frame dict already has
    /// the `kind: "encrypted"` discriminator the phone-side handler
    /// expects.
    init(
        send: NoiseCipherState,
        receive: NoiseCipherState,
        sendSignaling: @escaping (_ encryptedFrame: [String: Any]) -> Void,
        onFrame: @escaping (TakeoverFrame) -> Void,
        onError: @escaping (ChannelError) -> Void = { _ in }
    ) {
        self.send = send
        self.receive = receive
        self.sendSignaling = sendSignaling
        self.onFrame = onFrame
        self.onError = onError
    }

    /// Encrypt + wrap + ship `frame`. Throws if the channel is closed
    /// or the underlying CipherState's nonce counter is exhausted —
    /// the latter is a rekey signal in the Noise spec, not a recoverable
    /// error.
    func sendFrame(_ frame: TakeoverFrame) throws {
        guard !isClosed else { throw ChannelError.closed }
        let plaintext = try TakeoverFrameCodec.encode(frame)
        let ciphertext = try send.encrypt(plaintext)
        let seq = outboundSeq
        outboundSeq += 1
        sendSignaling([
            "kind": "encrypted",
            "seq": seq,
            "ciphertext": ciphertext.base64EncodedString(),
        ])
    }

    /// Hand a decoded SignalingMessage dict to the channel. Returns
    /// `true` if the message was an EncryptedFrame this channel owns
    /// (whether or not it decoded cleanly), `false` if it was a non-
    /// encrypted signaling type the caller should route elsewhere.
    @discardableResult
    func handleIncoming(_ signaling: [String: Any]) -> Bool {
        guard !isClosed else { return false }
        guard let kind = signaling["kind"] as? String, kind == "encrypted" else {
            return false
        }
        guard let seq = signaling["seq"] as? Int,
              let cipherB64 = signaling["ciphertext"] as? String else {
            onError(.malformed("missing seq or ciphertext"))
            return true
        }
        if seq <= lastIncomingSeq {
            onError(.replay(seq: seq, expected: lastIncomingSeq))
            return true
        }
        guard let cipherData = Data(base64Encoded: cipherB64) else {
            onError(.malformed("ciphertext is not valid base64"))
            return true
        }
        let plaintext: Data
        do {
            plaintext = try receive.decrypt(cipherData)
        } catch {
            onError(.aeadFailure("\(error)"))
            return true
        }
        let frame: TakeoverFrame
        do {
            frame = try TakeoverFrameCodec.decode(plaintext)
        } catch {
            onError(.decodeFailure("\(error)"))
            return true
        }
        lastIncomingSeq = seq
        onFrame(frame)
        return true
    }

    func close() {
        isClosed = true
    }
}
