export {
  generateKeyPair,
  deriveSharedSecret,
  encodeKey,
  decodeKey,
  type KeyPair,
} from './keys.js'

export {
  encrypt,
  decrypt,
  serializeEncrypted,
  deserializeEncrypted,
  type EncryptedMessage,
} from './cipher.js'

export {
  createSequenceState,
  allocateSeq,
  updateAck,
  validateSeq,
  buildAAD,
  type SequenceState,
} from './sequence.js'

export { generateSAS } from './sas.js'

export {
  HandshakeState,
  SymmetricState,
  CipherState,
  generateNoiseKeyPair,
  NOISE_PROTOCOL_NAME,
  DHLEN,
  HASHLEN,
  TAGLEN,
  type NoiseKeyPair,
  type HandshakeResult,
} from './noise.js'
