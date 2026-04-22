import simd

/// A resolved colour theme. Everything the renderer, terminal state machine,
/// and UI layer need to paint a terminal is here — no NSColor / AppKit.
struct Theme {
    let name: String
    let background: SIMD4<Float>
    let foreground: SIMD4<Float>
    let cursor: SIMD4<Float>
    let selection: SIMD4<Float>
    let accent: SIMD4<Float>
    let ansiStandard: [SIMD4<Float>]   // 8 colours
    let ansiBright: [SIMD4<Float>]     // 8 colours

    static func color(hex: UInt32, alpha: Float = 1) -> SIMD4<Float> {
        let r = Float((hex >> 16) & 0xFF) / 255
        let g = Float((hex >> 8) & 0xFF) / 255
        let b = Float(hex & 0xFF) / 255
        return SIMD4<Float>(r, g, b, alpha)
    }
}

extension Theme {
    static let builtins: [String: Theme] = [
        "catppuccin-mocha": .catppuccinMocha,
        "tokyo-night": .tokyoNight,
        "dracula": .dracula,
        "solarized-dark": .solarizedDark,
    ]

    static func named(_ name: String) -> Theme {
        builtins[name.lowercased()] ?? .catppuccinMocha
    }

    static let catppuccinMocha = Theme(
        name: "catppuccin-mocha",
        background: Theme.color(hex: 0x1E1E2E),
        foreground: Theme.color(hex: 0xCDD6F4),
        cursor: Theme.color(hex: 0xF5E0DC),
        selection: SIMD4<Float>(0.537, 0.706, 0.98, 0.35),
        accent: Theme.color(hex: 0x89B4FA),
        ansiStandard: [
            Theme.color(hex: 0x45475A),  // 0 Black
            Theme.color(hex: 0xF38BA8),  // 1 Red
            Theme.color(hex: 0xA6E3A1),  // 2 Green
            Theme.color(hex: 0xF9E2AF),  // 3 Yellow
            Theme.color(hex: 0x89B4FA),  // 4 Blue
            Theme.color(hex: 0xF5C2E7),  // 5 Magenta
            Theme.color(hex: 0x94E2D5),  // 6 Cyan
            Theme.color(hex: 0xBAC2DE),  // 7 White
        ],
        ansiBright: [
            Theme.color(hex: 0x585B70),
            Theme.color(hex: 0xF38BA8),
            Theme.color(hex: 0xA6E3A1),
            Theme.color(hex: 0xF9E2AF),
            Theme.color(hex: 0x89B4FA),
            Theme.color(hex: 0xF5C2E7),
            Theme.color(hex: 0x94E2D5),
            Theme.color(hex: 0xA6ADC8),
        ]
    )

    static let tokyoNight = Theme(
        name: "tokyo-night",
        background: Theme.color(hex: 0x1A1B26),
        foreground: Theme.color(hex: 0xC0CAF5),
        cursor: Theme.color(hex: 0xC0CAF5),
        selection: SIMD4<Float>(0.478, 0.549, 0.863, 0.35),
        accent: Theme.color(hex: 0x7AA2F7),
        ansiStandard: [
            Theme.color(hex: 0x15161E),
            Theme.color(hex: 0xF7768E),
            Theme.color(hex: 0x9ECE6A),
            Theme.color(hex: 0xE0AF68),
            Theme.color(hex: 0x7AA2F7),
            Theme.color(hex: 0xBB9AF7),
            Theme.color(hex: 0x7DCFFF),
            Theme.color(hex: 0xA9B1D6),
        ],
        ansiBright: [
            Theme.color(hex: 0x414868),
            Theme.color(hex: 0xF7768E),
            Theme.color(hex: 0x9ECE6A),
            Theme.color(hex: 0xE0AF68),
            Theme.color(hex: 0x7AA2F7),
            Theme.color(hex: 0xBB9AF7),
            Theme.color(hex: 0x7DCFFF),
            Theme.color(hex: 0xC0CAF5),
        ]
    )

    static let dracula = Theme(
        name: "dracula",
        background: Theme.color(hex: 0x282A36),
        foreground: Theme.color(hex: 0xF8F8F2),
        cursor: Theme.color(hex: 0xF8F8F2),
        selection: SIMD4<Float>(0.267, 0.286, 0.416, 0.55),
        accent: Theme.color(hex: 0xBD93F9),
        ansiStandard: [
            Theme.color(hex: 0x21222C),
            Theme.color(hex: 0xFF5555),
            Theme.color(hex: 0x50FA7B),
            Theme.color(hex: 0xF1FA8C),
            Theme.color(hex: 0xBD93F9),
            Theme.color(hex: 0xFF79C6),
            Theme.color(hex: 0x8BE9FD),
            Theme.color(hex: 0xF8F8F2),
        ],
        ansiBright: [
            Theme.color(hex: 0x6272A4),
            Theme.color(hex: 0xFF6E6E),
            Theme.color(hex: 0x69FF94),
            Theme.color(hex: 0xFFFFA5),
            Theme.color(hex: 0xD6ACFF),
            Theme.color(hex: 0xFF92DF),
            Theme.color(hex: 0xA4FFFF),
            Theme.color(hex: 0xFFFFFF),
        ]
    )

    static let solarizedDark = Theme(
        name: "solarized-dark",
        background: Theme.color(hex: 0x002B36),
        foreground: Theme.color(hex: 0x839496),
        cursor: Theme.color(hex: 0x93A1A1),
        selection: SIMD4<Float>(0.027, 0.212, 0.259, 0.55),
        accent: Theme.color(hex: 0x268BD2),
        ansiStandard: [
            Theme.color(hex: 0x073642),
            Theme.color(hex: 0xDC322F),
            Theme.color(hex: 0x859900),
            Theme.color(hex: 0xB58900),
            Theme.color(hex: 0x268BD2),
            Theme.color(hex: 0xD33682),
            Theme.color(hex: 0x2AA198),
            Theme.color(hex: 0xEEE8D5),
        ],
        ansiBright: [
            Theme.color(hex: 0x002B36),
            Theme.color(hex: 0xCB4B16),
            Theme.color(hex: 0x586E75),
            Theme.color(hex: 0x657B83),
            Theme.color(hex: 0x839496),
            Theme.color(hex: 0x6C71C4),
            Theme.color(hex: 0x93A1A1),
            Theme.color(hex: 0xFDF6E3),
        ]
    )
}
