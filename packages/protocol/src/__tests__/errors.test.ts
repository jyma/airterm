import { describe, it, expect } from 'vitest'
import { ErrorCode, ErrorMessage } from '../errors.js'

describe('ErrorCode', () => {
  it('has correct numeric values', () => {
    expect(ErrorCode.AUTH_FAILED).toBe(4001)
    expect(ErrorCode.DEVICE_NOT_PAIRED).toBe(4002)
    expect(ErrorCode.PAIR_CODE_INVALID).toBe(4003)
    expect(ErrorCode.TARGET_OFFLINE).toBe(4004)
    expect(ErrorCode.SESSION_NOT_FOUND).toBe(4005)
    expect(ErrorCode.COMMAND_BLOCKED).toBe(4006)
  })

  it('has error messages for all codes', () => {
    const codes = Object.values(ErrorCode)
    for (const code of codes) {
      expect(ErrorMessage[code]).toBeDefined()
      expect(typeof ErrorMessage[code]).toBe('string')
    }
  })
})
