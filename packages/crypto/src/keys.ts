import { x25519 } from '@noble/curves/ed25519'
import { randomBytes } from '@noble/ciphers/webcrypto'

export interface KeyPair {
  readonly publicKey: Uint8Array
  readonly privateKey: Uint8Array
}

/** Generate an X25519 key pair for ECDH key exchange */
export function generateKeyPair(): KeyPair {
  const privateKey = randomBytes(32)
  const publicKey = x25519.getPublicKey(privateKey)
  return { publicKey, privateKey }
}

/** Derive a shared secret from our private key and their public key */
export function deriveSharedSecret(
  privateKey: Uint8Array,
  theirPublicKey: Uint8Array,
): Uint8Array {
  return x25519.getSharedSecret(privateKey, theirPublicKey)
}

/** Encode a key to base64 */
export function encodeKey(key: Uint8Array): string {
  return Buffer.from(key).toString('base64')
}

/** Decode a key from base64 */
export function decodeKey(encoded: string): Uint8Array {
  return new Uint8Array(Buffer.from(encoded, 'base64'))
}

/**
 * Recover the X25519 public key from a stored 32-byte private key. Used
 * by the web phone-identity loader so we never have to persist both
 * halves in lockstep — re-deriving on load means truncation or partial
 * writes can't desync them.
 */
export function publicKeyFromPrivate(privateKey: Uint8Array): Uint8Array {
  return x25519.getPublicKey(privateKey)
}
