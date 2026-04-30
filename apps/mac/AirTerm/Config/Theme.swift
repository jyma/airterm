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
    /// Semantic colour roles used by chrome surfaces (status bar, command
    /// palette, future tab-bar segments) that want "the right hue for this
    /// theme" without hardcoding ANSI indices. Each role derives from the
    /// theme's standard palette so all 14 built-ins get sensible defaults
    /// for free; per-theme overrides can be added later by promoting these
    /// to stored properties.

    /// Primary user-facing accent — the colour of the prompt indicator (❯),
    /// active tab underline, focus ring, etc. Tracks `accent` so the
    /// signature hue of a theme stays consistent across chrome.
    var promptColor: SIMD4<Float> { accent }

    /// Git branch / metadata. ANSI magenta — matches starship convention.
    var gitColor: SIMD4<Float> { ansiStandard[5] }

    /// Modified / dirty marker. Yellow, the universal "attention" hue.
    var gitDirtyColor: SIMD4<Float> { ansiStandard[3] }

    /// Error state (non-zero exit, parse failure, …). ANSI red.
    var errorColor: SIMD4<Float> { ansiStandard[1] }

    /// Success state (zero exit, completed task). ANSI green.
    var successColor: SIMD4<Float> { ansiStandard[2] }

    /// Warning. ANSI yellow.
    var warningColor: SIMD4<Float> { ansiStandard[3] }

    /// Informational secondary text — quieter than `foreground` but still
    /// readable, used for cwd / time / proc count in the status bar.
    var infoColor: SIMD4<Float> { ansiStandard[4] }

    static let builtins: [String: Theme] = [
        "catppuccin-mocha": .catppuccinMocha,
        "tokyo-night": .tokyoNight,
        "dracula": .dracula,
        "solarized-dark": .solarizedDark,
        "gruvbox-dark": .gruvboxDark,
        "nord": .nord,
        "rose-pine": .rosePine,
        "one-dark": .oneDark,
        "catppuccin-latte": .catppuccinLatte,
        "tokyo-night-day": .tokyoNightDay,
        "rose-pine-dawn": .rosePineDawn,
        "gruvbox-light": .gruvboxLight,
        "one-light": .oneLight,
        "solarized-light": .solarizedLight,
    ]

    /// Stable, display order for menu / cycle UIs. Dark first, then light.
    static let builtinNames: [String] = [
        "catppuccin-mocha",
        "tokyo-night",
        "dracula",
        "solarized-dark",
        "gruvbox-dark",
        "nord",
        "rose-pine",
        "one-dark",
        "catppuccin-latte",
        "tokyo-night-day",
        "rose-pine-dawn",
        "gruvbox-light",
        "one-light",
        "solarized-light",
    ]

    /// Returns whether this theme is intended for light backgrounds. Used by
    /// the system-appearance auto-switch to pick the right member of a pair.
    var isLight: Bool {
        background.x + background.y + background.z > 1.5
    }

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

    /// Gruvbox Dark (hard contrast) — Pavel Pertsev, MIT.
    static let gruvboxDark = Theme(
        name: "gruvbox-dark",
        background: Theme.color(hex: 0x282828),
        foreground: Theme.color(hex: 0xEBDBB2),
        cursor: Theme.color(hex: 0xEBDBB2),
        selection: SIMD4<Float>(0.314, 0.286, 0.271, 0.55),
        accent: Theme.color(hex: 0xFABD2F),
        ansiStandard: [
            Theme.color(hex: 0x282828),
            Theme.color(hex: 0xCC241D),
            Theme.color(hex: 0x98971A),
            Theme.color(hex: 0xD79921),
            Theme.color(hex: 0x458588),
            Theme.color(hex: 0xB16286),
            Theme.color(hex: 0x689D6A),
            Theme.color(hex: 0xA89984),
        ],
        ansiBright: [
            Theme.color(hex: 0x928374),
            Theme.color(hex: 0xFB4934),
            Theme.color(hex: 0xB8BB26),
            Theme.color(hex: 0xFABD2F),
            Theme.color(hex: 0x83A598),
            Theme.color(hex: 0xD3869B),
            Theme.color(hex: 0x8EC07C),
            Theme.color(hex: 0xEBDBB2),
        ]
    )

    /// Nord — arctic-ice org, MIT.
    static let nord = Theme(
        name: "nord",
        background: Theme.color(hex: 0x2E3440),
        foreground: Theme.color(hex: 0xD8DEE9),
        cursor: Theme.color(hex: 0xD8DEE9),
        selection: SIMD4<Float>(0.298, 0.337, 0.416, 0.55),
        accent: Theme.color(hex: 0x88C0D0),
        ansiStandard: [
            Theme.color(hex: 0x3B4252),
            Theme.color(hex: 0xBF616A),
            Theme.color(hex: 0xA3BE8C),
            Theme.color(hex: 0xEBCB8B),
            Theme.color(hex: 0x81A1C1),
            Theme.color(hex: 0xB48EAD),
            Theme.color(hex: 0x88C0D0),
            Theme.color(hex: 0xE5E9F0),
        ],
        ansiBright: [
            Theme.color(hex: 0x4C566A),
            Theme.color(hex: 0xBF616A),
            Theme.color(hex: 0xA3BE8C),
            Theme.color(hex: 0xEBCB8B),
            Theme.color(hex: 0x81A1C1),
            Theme.color(hex: 0xB48EAD),
            Theme.color(hex: 0x8FBCBB),
            Theme.color(hex: 0xECEFF4),
        ]
    )

    /// Rosé Pine (Main) — rose-pine org, MIT.
    static let rosePine = Theme(
        name: "rose-pine",
        background: Theme.color(hex: 0x191724),
        foreground: Theme.color(hex: 0xE0DEF4),
        cursor: Theme.color(hex: 0xE0DEF4),
        selection: SIMD4<Float>(0.149, 0.137, 0.227, 0.55),
        accent: Theme.color(hex: 0xC4A7E7),
        ansiStandard: [
            Theme.color(hex: 0x26233A),
            Theme.color(hex: 0xEB6F92),
            Theme.color(hex: 0x31748F),
            Theme.color(hex: 0xF6C177),
            Theme.color(hex: 0x9CCFD8),
            Theme.color(hex: 0xC4A7E7),
            Theme.color(hex: 0xEBBCBA),
            Theme.color(hex: 0xE0DEF4),
        ],
        ansiBright: [
            Theme.color(hex: 0x6E6A86),
            Theme.color(hex: 0xEB6F92),
            Theme.color(hex: 0x31748F),
            Theme.color(hex: 0xF6C177),
            Theme.color(hex: 0x9CCFD8),
            Theme.color(hex: 0xC4A7E7),
            Theme.color(hex: 0xEBBCBA),
            Theme.color(hex: 0xE0DEF4),
        ]
    )

    /// One Dark (Atom) — GitHub/Atom, MIT.
    static let oneDark = Theme(
        name: "one-dark",
        background: Theme.color(hex: 0x282C34),
        foreground: Theme.color(hex: 0xABB2BF),
        cursor: Theme.color(hex: 0x528BFF),
        selection: SIMD4<Float>(0.243, 0.267, 0.325, 0.55),
        accent: Theme.color(hex: 0x61AFEF),
        ansiStandard: [
            Theme.color(hex: 0x282C34),
            Theme.color(hex: 0xE06C75),
            Theme.color(hex: 0x98C379),
            Theme.color(hex: 0xE5C07B),
            Theme.color(hex: 0x61AFEF),
            Theme.color(hex: 0xC678DD),
            Theme.color(hex: 0x56B6C2),
            Theme.color(hex: 0xABB2BF),
        ],
        ansiBright: [
            Theme.color(hex: 0x5C6370),
            Theme.color(hex: 0xE06C75),
            Theme.color(hex: 0x98C379),
            Theme.color(hex: 0xE5C07B),
            Theme.color(hex: 0x61AFEF),
            Theme.color(hex: 0xC678DD),
            Theme.color(hex: 0x56B6C2),
            Theme.color(hex: 0xFFFFFF),
        ]
    )

    // MARK: - Light themes

    /// Catppuccin Latte — Catppuccin org, MIT.
    static let catppuccinLatte = Theme(
        name: "catppuccin-latte",
        background: Theme.color(hex: 0xEFF1F5),
        foreground: Theme.color(hex: 0x4C4F69),
        cursor: Theme.color(hex: 0xDC8A78),
        selection: SIMD4<Float>(0.675, 0.690, 0.745, 0.55),
        accent: Theme.color(hex: 0x1E66F5),
        ansiStandard: [
            Theme.color(hex: 0x5C5F77),
            Theme.color(hex: 0xD20F39),
            Theme.color(hex: 0x40A02B),
            Theme.color(hex: 0xDF8E1D),
            Theme.color(hex: 0x1E66F5),
            Theme.color(hex: 0xEA76CB),
            Theme.color(hex: 0x179299),
            Theme.color(hex: 0xACB0BE),
        ],
        ansiBright: [
            Theme.color(hex: 0x6C6F85),
            Theme.color(hex: 0xD20F39),
            Theme.color(hex: 0x40A02B),
            Theme.color(hex: 0xDF8E1D),
            Theme.color(hex: 0x1E66F5),
            Theme.color(hex: 0xEA76CB),
            Theme.color(hex: 0x179299),
            Theme.color(hex: 0xBCC0CC),
        ]
    )

    /// Tokyo Night Day — enkia, MIT.
    static let tokyoNightDay = Theme(
        name: "tokyo-night-day",
        background: Theme.color(hex: 0xE1E2E7),
        foreground: Theme.color(hex: 0x3760BF),
        cursor: Theme.color(hex: 0x3760BF),
        selection: SIMD4<Float>(0.600, 0.655, 0.875, 0.45),
        accent: Theme.color(hex: 0x2E7DE9),
        ansiStandard: [
            Theme.color(hex: 0xB4B5B9),
            Theme.color(hex: 0xF52A65),
            Theme.color(hex: 0x587539),
            Theme.color(hex: 0x8C6C3E),
            Theme.color(hex: 0x2E7DE9),
            Theme.color(hex: 0x9854F1),
            Theme.color(hex: 0x007197),
            Theme.color(hex: 0x6172B0),
        ],
        ansiBright: [
            Theme.color(hex: 0xA1A6C5),
            Theme.color(hex: 0xF52A65),
            Theme.color(hex: 0x587539),
            Theme.color(hex: 0x8C6C3E),
            Theme.color(hex: 0x2E7DE9),
            Theme.color(hex: 0x9854F1),
            Theme.color(hex: 0x007197),
            Theme.color(hex: 0x3760BF),
        ]
    )

    /// Rosé Pine Dawn — rose-pine org, MIT.
    static let rosePineDawn = Theme(
        name: "rose-pine-dawn",
        background: Theme.color(hex: 0xFAF4ED),
        foreground: Theme.color(hex: 0x575279),
        cursor: Theme.color(hex: 0x575279),
        selection: SIMD4<Float>(0.875, 0.855, 0.851, 0.55),
        accent: Theme.color(hex: 0x907AA9),
        ansiStandard: [
            Theme.color(hex: 0xF2E9E1),
            Theme.color(hex: 0xB4637A),
            Theme.color(hex: 0x286983),
            Theme.color(hex: 0xEA9D34),
            Theme.color(hex: 0x56949F),
            Theme.color(hex: 0x907AA9),
            Theme.color(hex: 0xD7827E),
            Theme.color(hex: 0x575279),
        ],
        ansiBright: [
            Theme.color(hex: 0x9893A5),
            Theme.color(hex: 0xB4637A),
            Theme.color(hex: 0x286983),
            Theme.color(hex: 0xEA9D34),
            Theme.color(hex: 0x56949F),
            Theme.color(hex: 0x907AA9),
            Theme.color(hex: 0xD7827E),
            Theme.color(hex: 0x575279),
        ]
    )

    /// Gruvbox Light (hard) — Pavel Pertsev, MIT.
    static let gruvboxLight = Theme(
        name: "gruvbox-light",
        background: Theme.color(hex: 0xF9F5D7),
        foreground: Theme.color(hex: 0x3C3836),
        cursor: Theme.color(hex: 0x3C3836),
        selection: SIMD4<Float>(0.835, 0.769, 0.631, 0.55),
        accent: Theme.color(hex: 0x076678),
        ansiStandard: [
            Theme.color(hex: 0xFBF1C7),
            Theme.color(hex: 0xCC241D),
            Theme.color(hex: 0x98971A),
            Theme.color(hex: 0xD79921),
            Theme.color(hex: 0x458588),
            Theme.color(hex: 0xB16286),
            Theme.color(hex: 0x689D6A),
            Theme.color(hex: 0x7C6F64),
        ],
        ansiBright: [
            Theme.color(hex: 0x928374),
            Theme.color(hex: 0x9D0006),
            Theme.color(hex: 0x79740E),
            Theme.color(hex: 0xB57614),
            Theme.color(hex: 0x076678),
            Theme.color(hex: 0x8F3F71),
            Theme.color(hex: 0x427B58),
            Theme.color(hex: 0x3C3836),
        ]
    )

    /// One Light (Atom) — GitHub/Atom, MIT.
    static let oneLight = Theme(
        name: "one-light",
        background: Theme.color(hex: 0xFAFAFA),
        foreground: Theme.color(hex: 0x383A42),
        cursor: Theme.color(hex: 0x526EFF),
        selection: SIMD4<Float>(0.898, 0.898, 0.902, 0.55),
        accent: Theme.color(hex: 0x4078F2),
        ansiStandard: [
            Theme.color(hex: 0x383A42),
            Theme.color(hex: 0xE45649),
            Theme.color(hex: 0x50A14F),
            Theme.color(hex: 0xC18401),
            Theme.color(hex: 0x0184BC),
            Theme.color(hex: 0xA626A4),
            Theme.color(hex: 0x0997B3),
            Theme.color(hex: 0xFAFAFA),
        ],
        ansiBright: [
            Theme.color(hex: 0x4F525D),
            Theme.color(hex: 0xE45649),
            Theme.color(hex: 0x50A14F),
            Theme.color(hex: 0xC18401),
            Theme.color(hex: 0x0184BC),
            Theme.color(hex: 0xA626A4),
            Theme.color(hex: 0x0997B3),
            Theme.color(hex: 0xFFFFFF),
        ]
    )

    /// Solarized Light — Ethan Schoonover, MIT.
    static let solarizedLight = Theme(
        name: "solarized-light",
        background: Theme.color(hex: 0xFDF6E3),
        foreground: Theme.color(hex: 0x586E75),
        cursor: Theme.color(hex: 0x586E75),
        selection: SIMD4<Float>(0.933, 0.910, 0.835, 0.55),
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
