import { describe, it, expect } from 'vitest'
import { generatePairCode } from '../utils/pair-code.js'

describe('generatePairCode', () => {
  it('generates a 6-char code by default', () => {
    const code = generatePairCode()
    expect(code).toHaveLength(6)
  })

  it('generates code with custom length', () => {
    const code = generatePairCode(8)
    expect(code).toHaveLength(8)
  })

  it('only uses allowed characters (no ambiguous chars)', () => {
    for (let i = 0; i < 50; i++) {
      const code = generatePairCode()
      expect(code).toMatch(/^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]+$/)
      // Should not contain ambiguous characters
      expect(code).not.toMatch(/[IO01]/)
    }
  })

  it('generates unique codes', () => {
    const codes = new Set(Array.from({ length: 100 }, () => generatePairCode()))
    expect(codes.size).toBeGreaterThan(90) // Allow some collisions in 6-char codes
  })
})
