import Foundation

/// Drives the *Mac side* of the Noise IK pairing handshake. Mirror of the
/// web-side `NoisePairDriver` (apps/web/src/lib/noise-pair-driver.ts) —
/// pure logic with IO injected so the caller (PairingWindow) can wire it
/// to whatever channel it has open. Tests can drive it with an in-process
/// initiator.
///
/// Lifecycle:
///   1. `init(...)` builds a Noise IK responder over the Mac's static
///      keypair. It does NOT need to know the initiator's static — IK
///      lets the responder learn it from message A.
///   2. The caller delivers each inbound `SignalingMessage` payload (as a
///      decoded dictionary, since Swift doesn't share the TS protocol
///      types) to `processIncomingFrame(noiseFrame:)`. On stage 1, the
///      responder reads the initiator's message A, generates message B,
///      hands it to the caller's `sendFrame` callback, and finalises the
///      transport CipherStates. From that point onward, the
///      `transportResult` is non-nil and the driver is `completed`.
///   3. The caller can read `learnedInitiatorStaticPublicKey` after
///      stage 1 completes — that's the phone's static, ready to be
///      stored alongside the PairedPhone record.
final class NoisePairResponder {
    /// Wire-format frame as decoded from a `SignalingMessage` of kind
    /// `noise`. Caller decodes the relay envelope + SequencedMessage +
    /// SignalingMessage JSON before reaching us.
    struct InboundNoiseFrame {
        let stage: Int
        let noisePayloadBase64: String
    }

    enum NoisePairResponderError: Error, CustomStringConvertible {
        case wrongStage(got: Int)
        case alreadyCompleted
        case badBase64
        case readMessageAFailed(String)
        case writeMessageBFailed(String)

        var description: String {
            switch self {
            case .wrongStage(let g): return "expected stage 1, got \(g)"
            case .alreadyCompleted: return "responder already completed handshake"
            case .badBase64: return "stage-1 noisePayload was not valid base64"
            case .readMessageAFailed(let s): return "read message A failed: \(s)"
            case .writeMessageBFailed(let s): return "write message B failed: \(s)"
            }
        }
    }

    enum State { case awaitingA, completed, failed }

    private let handshake: NoiseHandshakeState
    private let sendFrame: (_ stage: Int, _ noisePayloadBase64: String) -> Void
    private(set) var state: State = .awaitingA
    private(set) var transportResult: NoiseHandshakeState.Result?
    private(set) var learnedInitiatorStaticPublicKey: Data?
    private(set) var payloadFromA: Data?

    /// `prologue` MUST match the initiator's prologue or the AEAD on the
    /// very first encrypted field of message A fails. For AirTerm pair
    /// flow this is empty by default; callers can pass QR bytes if they
    /// want strict channel binding.
    init(
        macStatic: NoiseKeyPair,
        prologue: Data = Data(),
        sendFrame: @escaping (_ stage: Int, _ noisePayloadBase64: String) -> Void
    ) throws {
        self.handshake = try NoiseHandshakeState(
            isInitiator: false,
            prologue: prologue,
            s: macStatic
        )
        self.sendFrame = sendFrame
    }

    /// Feed one inbound Noise frame. On stage 1, runs the responder
    /// half-handshake and emits stage 2 via the caller's sendFrame
    /// callback. Idempotent for stage 1: a re-delivered stage 1 (which
    /// shouldn't happen on a healthy WS) is rejected with
    /// `.alreadyCompleted` so the caller can detect protocol confusion.
    @discardableResult
    func processIncomingFrame(_ frame: InboundNoiseFrame) throws -> Bool {
        switch state {
        case .completed, .failed:
            throw NoisePairResponderError.alreadyCompleted
        case .awaitingA:
            break
        }
        guard frame.stage == 1 else {
            throw NoisePairResponderError.wrongStage(got: frame.stage)
        }
        guard let messageA = Data(base64Encoded: frame.noisePayloadBase64) else {
            state = .failed
            throw NoisePairResponderError.badBase64
        }
        let recovered: Data
        do {
            recovered = try handshake.readMessageA(messageA)
        } catch {
            state = .failed
            throw NoisePairResponderError.readMessageAFailed("\(error)")
        }
        let messageB: Data
        do {
            // No payload sent in stage 2 — the caller can extend this
            // later (e.g. server-confirmed device id) without a wire
            // format change since the field is already AEAD-protected.
            messageB = try handshake.writeMessageB(payload: Data())
        } catch {
            state = .failed
            throw NoisePairResponderError.writeMessageBFailed("\(error)")
        }
        sendFrame(2, messageB.base64EncodedString())
        transportResult = handshake.finalize()
        learnedInitiatorStaticPublicKey = handshake.rs
        payloadFromA = recovered
        state = .completed
        return true
    }
}
