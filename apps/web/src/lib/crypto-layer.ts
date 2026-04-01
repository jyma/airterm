/**
 * E2EE Crypto Layer for Web client.
 * Wraps @airterm/crypto to provide encrypt/decrypt for WebSocket messages.
 */

import {
  generateKeyPair,
  deriveSharedSecret,
  encrypt,
  decrypt,
  serializeEncrypted,
  deserializeEncrypted,
  encodeKey,
  decodeKey,
  createSequenceState,
  allocateSeq,
  updateAck,
  validateSeq,
  buildAAD,
  generateSAS,
  type SequenceState,
} from '@airterm/crypto'
import { storeKey, loadKey } from './key-store.js'

export interface CryptoLayer {
  /** Our public key (to share during pairing) */
  readonly publicKey: string

  /** Set the peer's public key after pairing */
  setPeerPublicKey(peerPublicKeyBase64: string): void

  /** Encrypt a message payload */
  encryptPayload(plaintext: string): string

  /** Decrypt a message payload */
  decryptPayload(encrypted: string): string

  /** Get SAS code for verification */
  getSASCode(): string | null

  /** Whether E2EE is active */
  readonly isActive: boolean
}

export async function createCryptoLayer(): Promise<CryptoLayer> {
  // Try to load existing key pair, or generate new one
  let privateKey = await loadKey('privateKey')
  let publicKey = await loadKey('publicKey')

  if (!privateKey || !publicKey) {
    const kp = generateKeyPair()
    privateKey = kp.privateKey
    publicKey = kp.publicKey
    await storeKey('privateKey', privateKey)
    await storeKey('publicKey', publicKey)
  }

  let sharedSecret: Uint8Array | null = null
  let peerPublicKey: Uint8Array | null = null
  let sendState: SequenceState = createSequenceState()
  let recvState: SequenceState = createSequenceState()

  return {
    get publicKey() {
      return encodeKey(publicKey!)
    },

    get isActive() {
      return sharedSecret !== null
    },

    setPeerPublicKey(peerPublicKeyBase64: string) {
      peerPublicKey = decodeKey(peerPublicKeyBase64)
      sharedSecret = deriveSharedSecret(privateKey!, peerPublicKey)
    },

    encryptPayload(plaintext: string): string {
      if (!sharedSecret) {
        // No E2EE — return base64 plaintext (MVP fallback)
        return btoa(unescape(encodeURIComponent(plaintext)))
      }

      const { state: newState, seq } = allocateSeq(sendState)
      sendState = newState
      const aad = buildAAD(seq, sendState.lastAck)

      const data = new TextEncoder().encode(plaintext)
      const encrypted = encrypt(sharedSecret, data, aad)
      const serialized = serializeEncrypted(encrypted)

      // Prepend seq (4 bytes) + ack (4 bytes) to the serialized data
      const result = new Uint8Array(8 + serialized.length)
      const view = new DataView(result.buffer)
      view.setUint32(0, seq, false)
      view.setUint32(4, sendState.lastAck, false)
      result.set(serialized, 8)

      return bufferToBase64(result)
    },

    decryptPayload(encrypted: string): string {
      if (!sharedSecret) {
        // No E2EE — decode base64 plaintext (MVP fallback)
        return decodeURIComponent(escape(atob(encrypted)))
      }

      const data = base64ToBuffer(encrypted)
      const view = new DataView(data.buffer, data.byteOffset)
      const seq = view.getUint32(0, false)
      const ack = view.getUint32(4, false)

      // Validate sequence number
      const validation = validateSeq(recvState, seq)
      if (validation.result === 'duplicate') {
        throw new Error(`Duplicate message: seq=${seq}`)
      }
      recvState = validation.state
      sendState = updateAck(sendState, seq)

      const aad = buildAAD(seq, ack)
      const encryptedMsg = deserializeEncrypted(data.slice(8))
      const plaintext = decrypt(sharedSecret, encryptedMsg, aad)

      return new TextDecoder().decode(plaintext)
    },

    getSASCode(): string | null {
      if (!peerPublicKey || !publicKey) return null
      return generateSAS(publicKey, peerPublicKey)
    },
  }
}

function bufferToBase64(buffer: Uint8Array): string {
  let binary = ''
  for (let i = 0; i < buffer.length; i++) {
    binary += String.fromCharCode(buffer[i])
  }
  return btoa(binary)
}

function base64ToBuffer(base64: string): Uint8Array {
  const binary = atob(base64)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i)
  }
  return bytes
}
