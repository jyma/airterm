import { chacha20poly1305 } from '@noble/ciphers/chacha'
import { randomBytes } from '@noble/ciphers/webcrypto'

const NONCE_LENGTH = 12
const PAD_BLOCK_SIZE = 1024 // Pad to 1KB boundaries to prevent size-based side-channel

export interface EncryptedMessage {
  readonly nonce: Uint8Array
  readonly ciphertext: Uint8Array
}

/**
 * Encrypt a plaintext message using ChaCha20-Poly1305.
 * Each message uses a unique random nonce.
 * Optionally includes AAD (additional authenticated data) for seq/ack binding.
 */
export function encrypt(
  sharedSecret: Uint8Array,
  plaintext: Uint8Array,
  aad?: Uint8Array,
): EncryptedMessage {
  const padded = padMessage(plaintext)
  const nonce = randomBytes(NONCE_LENGTH)
  const cipher = chacha20poly1305(sharedSecret, nonce, aad)
  const ciphertext = cipher.encrypt(padded)
  return { nonce, ciphertext }
}

/**
 * Decrypt a message using ChaCha20-Poly1305.
 * Verifies authentication tag and AAD.
 */
export function decrypt(
  sharedSecret: Uint8Array,
  encrypted: EncryptedMessage,
  aad?: Uint8Array,
): Uint8Array {
  const cipher = chacha20poly1305(sharedSecret, encrypted.nonce, aad)
  const padded = cipher.decrypt(encrypted.ciphertext)
  return unpadMessage(padded)
}

/**
 * Serialize encrypted message to bytes: [nonce (12)] [ciphertext (N)]
 */
export function serializeEncrypted(msg: EncryptedMessage): Uint8Array {
  const result = new Uint8Array(NONCE_LENGTH + msg.ciphertext.length)
  result.set(msg.nonce, 0)
  result.set(msg.ciphertext, NONCE_LENGTH)
  return result
}

/**
 * Deserialize encrypted message from bytes
 */
export function deserializeEncrypted(data: Uint8Array): EncryptedMessage {
  return {
    nonce: data.slice(0, NONCE_LENGTH),
    ciphertext: data.slice(NONCE_LENGTH),
  }
}

/** Pad message to PAD_BLOCK_SIZE boundary to prevent size side-channel */
function padMessage(data: Uint8Array): Uint8Array {
  // Format: [4-byte length (big-endian)] [data] [padding zeros]
  const totalLen = 4 + data.length
  const paddedLen = Math.ceil(totalLen / PAD_BLOCK_SIZE) * PAD_BLOCK_SIZE
  const result = new Uint8Array(paddedLen)
  const view = new DataView(result.buffer)
  view.setUint32(0, data.length, false) // big-endian length
  result.set(data, 4)
  return result
}

/** Remove padding from message */
function unpadMessage(padded: Uint8Array): Uint8Array {
  const view = new DataView(padded.buffer, padded.byteOffset)
  const length = view.getUint32(0, false)
  if (length > padded.length - 4) {
    throw new Error('Invalid padded message: length exceeds data')
  }
  return padded.slice(4, 4 + length)
}
