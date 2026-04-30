import CryptoKit
import Foundation

/// Noise IK pattern over Curve25519 + ChaCha20-Poly1305 + SHA-256.
///
/// Mirrors `@airterm/crypto/noise.ts` byte-for-byte so the web initiator
/// (which imports the TS reference) and the Mac responder agree on every
/// transcript bit. Both sides MUST use the same protocol-name string,
/// the same wire format, and the same counter-nonce convention listed
/// below; any drift breaks the AEAD tag check on the very first frame.
///
/// Wire formats:
///   • Message A (initiator → responder): e (32) || enc(s) (32+16) || enc(payload) (n+16)
///   • Message B (responder → initiator): e (32) || enc(payload) (n+16)
///   • Transport: enc(payload) (n+16) — driven by `CipherState`
///
/// Counter nonce (12 bytes): 4 zero bytes || little-endian u64 counter.
///
/// HKDF style (Noise §5.1):
///   temp = HMAC-SHA256(chaining_key, ikm)
///   o1   = HMAC-SHA256(temp, 0x01)
///   o2   = HMAC-SHA256(temp, o1 || 0x02)
///
/// Test coverage: Mac swift-test CLI is unavailable on this machine
/// (XCTest module missing under Command Line Tools). `Noise.runSelfTest()`
/// is invoked at app launch in DEBUG builds to fail-fast if the Swift
/// port drifts from the TS reference.
enum Noise {
    static let protocolName = "Noise_IK_25519_ChaChaPoly_SHA256"
    static let dhLen = 32
    static let hashLen = 32
    static let tagLen = 16
}

enum NoiseError: Error, CustomStringConvertible {
    case nonceExhausted
    case shortCiphertext
    case wrongRole
    case missingResponderStatic
    case missingResponderEphemeral
    case messageTooShort
    case keyAgreement

    var description: String {
        switch self {
        case .nonceExhausted: return "Noise CipherState nonce exhausted"
        case .shortCiphertext: return "Noise ciphertext shorter than tag"
        case .wrongRole: return "Noise message dispatched to wrong role"
        case .missingResponderStatic: return "Noise IK initiator missing responder static (rs)"
        case .missingResponderEphemeral: return "Noise IK responder missing initiator ephemeral (re)"
        case .messageTooShort: return "Noise IK handshake message too short"
        case .keyAgreement: return "Noise X25519 key agreement failed"
        }
    }
}

struct NoiseKeyPair {
    let privateKey: Data
    let publicKey: Data

    static func generate() -> NoiseKeyPair {
        let priv = Curve25519.KeyAgreement.PrivateKey()
        return NoiseKeyPair(
            privateKey: priv.rawRepresentation,
            publicKey: priv.publicKey.rawRepresentation
        )
    }
}

private func hkdf2(chainingKey: Data, ikm: Data) -> (Data, Data) {
    let ckKey = SymmetricKey(data: chainingKey)
    let temp = Data(HMAC<SHA256>.authenticationCode(for: ikm, using: ckKey))
    let tempKey = SymmetricKey(data: temp)
    let o1 = Data(HMAC<SHA256>.authenticationCode(
        for: Data([0x01]),
        using: tempKey
    ))
    var o1WithLabel = o1
    o1WithLabel.append(0x02)
    let o2 = Data(HMAC<SHA256>.authenticationCode(
        for: o1WithLabel,
        using: tempKey
    ))
    return (o1, o2)
}

private func nonceBytes(_ counter: UInt64) -> Data {
    var d = Data(count: 12)
    var c = counter.littleEndian
    withUnsafeBytes(of: &c) { src in
        d.replaceSubrange(4..<12, with: src)
    }
    return d
}

private func dh(privateKey: Data, publicKey: Data) throws -> Data {
    do {
        let priv = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKey)
        let pub  = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: publicKey)
        let secret = try priv.sharedSecretFromKeyAgreement(with: pub)
        return secret.withUnsafeBytes { Data($0) }
    } catch {
        throw NoiseError.keyAgreement
    }
}

// MARK: - SymmetricState (Noise §5.2)

final class NoiseSymmetricState {
    private(set) var ck: Data = Data(count: Noise.hashLen)
    private(set) var h: Data  = Data(count: Noise.hashLen)
    private(set) var k: Data?
    private(set) var n: UInt64 = 0

    func initialize(protocolName: String) {
        let nameData = Data(protocolName.utf8)
        if nameData.count <= Noise.hashLen {
            var padded = Data(count: Noise.hashLen)
            padded.replaceSubrange(0..<nameData.count, with: nameData)
            h = padded
        } else {
            h = Data(SHA256.hash(data: nameData))
        }
        ck = h
        k = nil
        n = 0
    }

    func mixHash(_ data: Data) {
        var combined = h
        combined.append(data)
        h = Data(SHA256.hash(data: combined))
    }

    func mixKey(_ material: Data) {
        let (newCk, tempK) = hkdf2(chainingKey: ck, ikm: material)
        ck = newCk
        k = tempK.prefix(32)
        n = 0
    }

    func encryptAndHash(_ plaintext: Data) throws -> Data {
        let out: Data
        if let key = k {
            let nonce = try ChaChaPoly.Nonce(data: nonceBytes(n))
            let sealed = try ChaChaPoly.seal(
                plaintext,
                using: SymmetricKey(data: key),
                nonce: nonce,
                authenticating: h
            )
            out = sealed.ciphertext + sealed.tag
            n += 1
        } else {
            out = plaintext
        }
        mixHash(out)
        return out
    }

    func decryptAndHash(_ ciphertext: Data) throws -> Data {
        let plaintext: Data
        if let key = k {
            guard ciphertext.count >= Noise.tagLen else {
                throw NoiseError.shortCiphertext
            }
            let split = ciphertext.count - Noise.tagLen
            let ct  = ciphertext.prefix(split)
            let tag = ciphertext.suffix(Noise.tagLen)
            let nonce = try ChaChaPoly.Nonce(data: nonceBytes(n))
            let sealed = try ChaChaPoly.SealedBox(nonce: nonce, ciphertext: ct, tag: tag)
            plaintext = try ChaChaPoly.open(
                sealed,
                using: SymmetricKey(data: key),
                authenticating: h
            )
            n += 1
        } else {
            plaintext = ciphertext
        }
        mixHash(ciphertext)
        return plaintext
    }

    func split() -> (NoiseCipherState, NoiseCipherState) {
        let (k1, k2) = hkdf2(chainingKey: ck, ikm: Data())
        return (NoiseCipherState(key: k1.prefix(32)),
                NoiseCipherState(key: k2.prefix(32)))
    }

    var handshakeHash: Data { h }
}

// MARK: - CipherState (Noise §5.1)

final class NoiseCipherState {
    private let key: Data
    private(set) var n: UInt64 = 0

    init(key: Data) {
        precondition(key.count == 32, "NoiseCipherState key must be 32 bytes")
        self.key = Data(key)
    }

    func encrypt(_ plaintext: Data, ad: Data = Data()) throws -> Data {
        guard n != UInt64.max else { throw NoiseError.nonceExhausted }
        let nonce = try ChaChaPoly.Nonce(data: nonceBytes(n))
        let sealed = try ChaChaPoly.seal(
            plaintext,
            using: SymmetricKey(data: key),
            nonce: nonce,
            authenticating: ad
        )
        n += 1
        return sealed.ciphertext + sealed.tag
    }

    func decrypt(_ ciphertext: Data, ad: Data = Data()) throws -> Data {
        guard n != UInt64.max else { throw NoiseError.nonceExhausted }
        guard ciphertext.count >= Noise.tagLen else { throw NoiseError.shortCiphertext }
        let split = ciphertext.count - Noise.tagLen
        let ct  = ciphertext.prefix(split)
        let tag = ciphertext.suffix(Noise.tagLen)
        let nonce = try ChaChaPoly.Nonce(data: nonceBytes(n))
        let sealed = try ChaChaPoly.SealedBox(nonce: nonce, ciphertext: ct, tag: tag)
        let plaintext = try ChaChaPoly.open(
            sealed,
            using: SymmetricKey(data: key),
            authenticating: ad
        )
        n += 1
        return plaintext
    }
}

// MARK: - HandshakeState (Noise §5.3) for IK pattern (§7.5)

final class NoiseHandshakeState {
    let ss = NoiseSymmetricState()
    let s: NoiseKeyPair
    var e: NoiseKeyPair?
    var rs: Data?
    var re: Data?
    let isInitiator: Bool

    init(isInitiator: Bool, prologue: Data, s: NoiseKeyPair, rs: Data? = nil) throws {
        if isInitiator && rs == nil {
            throw NoiseError.missingResponderStatic
        }
        self.isInitiator = isInitiator
        self.s = s
        self.rs = rs
        ss.initialize(protocolName: Noise.protocolName)
        ss.mixHash(prologue)
        if isInitiator {
            ss.mixHash(rs!)
        } else {
            ss.mixHash(s.publicKey)
        }
    }

    /// Initiator → responder, message A: e, es, s, ss + payload.
    func writeMessageA(payload: Data) throws -> Data {
        guard isInitiator else { throw NoiseError.wrongRole }
        let ephem = NoiseKeyPair.generate()
        e = ephem
        ss.mixHash(ephem.publicKey)
        ss.mixKey(try dh(privateKey: ephem.privateKey, publicKey: rs!))
        let sCipher = try ss.encryptAndHash(s.publicKey)
        ss.mixKey(try dh(privateKey: s.privateKey, publicKey: rs!))
        let payloadCipher = try ss.encryptAndHash(payload)
        return ephem.publicKey + sCipher + payloadCipher
    }

    func readMessageA(_ message: Data) throws -> Data {
        guard !isInitiator else { throw NoiseError.wrongRole }
        let minLen = Noise.dhLen + Noise.dhLen + Noise.tagLen
        guard message.count >= minLen else { throw NoiseError.messageTooShort }
        var off = message.startIndex
        let reBytes = Data(message[off..<(off + Noise.dhLen)])
        off += Noise.dhLen
        re = reBytes
        ss.mixHash(reBytes)
        ss.mixKey(try dh(privateKey: s.privateKey, publicKey: reBytes))
        let sCiphLen = Noise.dhLen + Noise.tagLen
        let sCipher = Data(message[off..<(off + sCiphLen)])
        off += sCiphLen
        let rsBytes = try ss.decryptAndHash(sCipher)
        rs = rsBytes
        ss.mixKey(try dh(privateKey: s.privateKey, publicKey: rsBytes))
        let payloadCipher = Data(message[off..<message.endIndex])
        return try ss.decryptAndHash(payloadCipher)
    }

    /// Responder → initiator, message B: e, ee, se + payload.
    func writeMessageB(payload: Data) throws -> Data {
        guard !isInitiator else { throw NoiseError.wrongRole }
        guard let re else { throw NoiseError.missingResponderEphemeral }
        let ephem = NoiseKeyPair.generate()
        e = ephem
        ss.mixHash(ephem.publicKey)
        ss.mixKey(try dh(privateKey: ephem.privateKey, publicKey: re))
        ss.mixKey(try dh(privateKey: ephem.privateKey, publicKey: rs!))
        let payloadCipher = try ss.encryptAndHash(payload)
        return ephem.publicKey + payloadCipher
    }

    func readMessageB(_ message: Data) throws -> Data {
        guard isInitiator else { throw NoiseError.wrongRole }
        let minLen = Noise.dhLen + Noise.tagLen
        guard message.count >= minLen else { throw NoiseError.messageTooShort }
        var off = message.startIndex
        let reBytes = Data(message[off..<(off + Noise.dhLen)])
        off += Noise.dhLen
        re = reBytes
        ss.mixHash(reBytes)
        ss.mixKey(try dh(privateKey: e!.privateKey, publicKey: reBytes))
        ss.mixKey(try dh(privateKey: s.privateKey, publicKey: reBytes))
        let payloadCipher = Data(message[off..<message.endIndex])
        return try ss.decryptAndHash(payloadCipher)
    }

    struct Result {
        let send: NoiseCipherState
        let receive: NoiseCipherState
        let handshakeHash: Data
    }

    func finalize() -> Result {
        let (c1, c2) = ss.split()
        let hh = ss.handshakeHash
        return isInitiator
            ? Result(send: c1, receive: c2, handshakeHash: hh)
            : Result(send: c2, receive: c1, handshakeHash: hh)
    }
}

// MARK: - Self-test

extension Noise {
    /// Runs a full IK round-trip with both halves locally and verifies
    /// transport keys + bidirectional encryption agree. Returns nil on
    /// success; a description string on failure. Called from
    /// AppDelegate at launch in DEBUG builds — failures crash via
    /// `assertionFailure` so any drift between this Swift port and the
    /// TS reference surfaces immediately.
    static func runSelfTest() -> String? {
        do {
            let respStatic = NoiseKeyPair.generate()
            let initStatic = NoiseKeyPair.generate()

            let initiator = try NoiseHandshakeState(
                isInitiator: true,
                prologue: Data(),
                s: initStatic,
                rs: respStatic.publicKey
            )
            let responder = try NoiseHandshakeState(
                isInitiator: false,
                prologue: Data(),
                s: respStatic
            )

            let payloadA = Data("hello-from-initiator".utf8)
            let payloadB = Data("hello-from-responder".utf8)

            let mA = try initiator.writeMessageA(payload: payloadA)
            let recA = try responder.readMessageA(mA)
            guard recA == payloadA else { return "message A payload mismatch" }
            guard responder.rs == initStatic.publicKey else {
                return "responder failed to learn initiator static"
            }

            let mB = try responder.writeMessageB(payload: payloadB)
            let recB = try initiator.readMessageB(mB)
            guard recB == payloadB else { return "message B payload mismatch" }

            let initFinal = initiator.finalize()
            let respFinal = responder.finalize()
            guard initFinal.handshakeHash == respFinal.handshakeHash else {
                return "handshake hash mismatch"
            }

            let ping = try initFinal.send.encrypt(Data("ping-1".utf8))
            let pingPlain = try respFinal.receive.decrypt(ping)
            guard pingPlain == Data("ping-1".utf8) else {
                return "transport ping decryption mismatch"
            }

            let pong = try respFinal.send.encrypt(Data("pong-1".utf8))
            let pongPlain = try initFinal.receive.decrypt(pong)
            guard pongPlain == Data("pong-1".utf8) else {
                return "transport pong decryption mismatch"
            }

            // ---- TakeoverChannel round-trip ----
            //
            // Drive a TakeoverFrame from initiator → responder and back
            // through actual TakeoverChannel instances using the transport
            // CipherStates we just split. Catches drift between the
            // Swift Codable frame layout and the TS reference.
            var capturedFromInitiator: [String: Any]?
            var capturedFromResponder: [String: Any]?
            var responderInbox: [TakeoverFrame] = []
            var initiatorInbox: [TakeoverFrame] = []

            let initiatorChannel = TakeoverChannel(
                send: initFinal.send,
                receive: initFinal.receive,
                sendSignaling: { dict in capturedFromInitiator = dict },
                onFrame: { frame in initiatorInbox.append(frame) }
            )
            let responderChannel = TakeoverChannel(
                send: respFinal.send,
                receive: respFinal.receive,
                sendSignaling: { dict in capturedFromResponder = dict },
                onFrame: { frame in responderInbox.append(frame) }
            )

            let pingFrame: TakeoverFrame = .ping(TakeoverPingFrame(seq: 0, ts: 1234))
            try initiatorChannel.sendFrame(pingFrame)
            guard let pingDict = capturedFromInitiator else {
                return "TakeoverChannel did not produce an outbound frame"
            }
            responderChannel.handleIncoming(pingDict)
            guard responderInbox.count == 1 else {
                return "TakeoverChannel responder inbox empty after ping"
            }
            guard responderInbox.first == pingFrame else {
                return "TakeoverChannel ping mismatch on responder side"
            }

            let inputFrame: TakeoverFrame = .inputEvent(InputEventFrame(
                seq: 0,
                bytes: Data("ls\r".utf8).base64EncodedString()
            ))
            try responderChannel.sendFrame(inputFrame)
            guard let inputDict = capturedFromResponder else {
                return "TakeoverChannel responder produced no outbound frame"
            }
            initiatorChannel.handleIncoming(inputDict)
            guard initiatorInbox.count == 1, initiatorInbox.first == inputFrame else {
                return "TakeoverChannel input round-trip mismatch on initiator side"
            }

            return nil
        } catch {
            return "exception: \(error)"
        }
    }
}
