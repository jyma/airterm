/**
 * SAS (Short Authentication String) for verifying key exchange.
 * After pairing, both sides compute a 4-digit code from the shared secret.
 * User visually confirms both codes match → MITM protection.
 */

import { createHash } from 'node:crypto'

/**
 * Generate a 4-digit SAS code from two public keys.
 * Both sides compute this independently — if they match, no MITM occurred.
 */
export function generateSAS(
  macPublicKey: Uint8Array,
  phonePublicKey: Uint8Array,
): string {
  const combined = concatSorted(macPublicKey, phonePublicKey)
  const hash = createHash('sha256').update(combined).digest()

  // Take first 2 bytes → 4 decimal digits
  const value = (hash[0] << 8) | hash[1]
  const code = (value % 10000).toString().padStart(4, '0')

  return code
}

/** Concatenate two byte arrays in sorted order (for deterministic output) */
function concatSorted(a: Uint8Array, b: Uint8Array): Uint8Array {
  const order = compareBytes(a, b)
  const first = order <= 0 ? a : b
  const second = order <= 0 ? b : a
  const result = new Uint8Array(first.length + second.length)
  result.set(first, 0)
  result.set(second, first.length)
  return result
}

/** Compare two byte arrays lexicographically */
function compareBytes(a: Uint8Array, b: Uint8Array): number {
  const len = Math.min(a.length, b.length)
  for (let i = 0; i < len; i++) {
    if (a[i] !== b[i]) return a[i] - b[i]
  }
  return a.length - b.length
}
