import Foundation

/// Display width (in terminal columns) for a `Character` based on Unicode
/// East Asian Width (UAX #11) plus the common emoji blocks that modern
/// terminals render as fullwidth. Ambiguous (A) characters default to 1
/// to match iTerm2 / Terminal.app / xterm behaviour for CJK locales.
enum CharWidth {
    static func of(_ char: Character) -> Int {
        guard let scalar = char.unicodeScalars.first else { return 1 }
        return isWide(scalar.value) ? 2 : 1
    }

    private static func isWide(_ v: UInt32) -> Bool {
        switch v {
        case 0x1100...0x115F,            // Hangul Jamo
             0x2329...0x232A,            // Angle brackets
             0x2E80...0x303E,            // CJK Radicals, Kangxi, etc.
             0x3041...0x33FF,            // Hiragana, Katakana, Bopomofo, ...
             0x3400...0x4DBF,            // CJK Unified Ideographs Ext A
             0x4E00...0x9FFF,            // CJK Unified Ideographs
             0xA000...0xA4CF,            // Yi Syllables
             0xAC00...0xD7A3,            // Hangul Syllables
             0xF900...0xFAFF,            // CJK Compatibility Ideographs
             0xFE10...0xFE19,            // Vertical Forms
             0xFE30...0xFE6F,            // CJK Compatibility Forms
             0xFF00...0xFF60,            // Fullwidth Forms
             0xFFE0...0xFFE6,            // Fullwidth Signs
             0x1F300...0x1F64F,          // Misc Symbols & Pictographs, Emoticons
             0x1F680...0x1F6FF,          // Transport & Map
             0x1F900...0x1F9FF,          // Supplemental Symbols & Pictographs
             0x20000...0x2FFFD,          // CJK Ext B-F
             0x30000...0x3FFFD:          // CJK Ext G
            return true
        default:
            return false
        }
    }
}
