import Foundation

/// Mac-side mirror of `packages/protocol/src/takeover.ts`. Both sides
/// MUST agree on field names and JSON shape — the phone's xterm.js
/// renderer decodes these structures directly and any drift surfaces
/// as an immediate AEAD-passes-but-render-fails bug.
///
/// We hand-roll Codable for the discriminated union so the on-wire JSON
/// matches the TS reference 1:1 (`{"kind": "screen_snapshot", ...}`)
/// without an extra "case" envelope key Swift's automatic enum coding
/// would otherwise insert.

// ---- Style flag bits (mirror Services/Cell.swift::CellAttributes) ----

enum TakeoverAttr {
    static let bold:          UInt8 = 0x01
    static let dim:           UInt8 = 0x02
    static let italic:        UInt8 = 0x04
    static let underline:     UInt8 = 0x08
    static let reverse:       UInt8 = 0x10
    static let strikethrough: UInt8 = 0x20
}

// ---- Cell + cursor primitives ----

struct CellFrame: Codable, Equatable {
    let ch: String
    let fg: Int?
    let bg: Int?
    let attrs: UInt8?
    let width: Int?

    init(ch: String, fg: Int? = nil, bg: Int? = nil, attrs: UInt8? = nil, width: Int? = nil) {
        self.ch = ch
        self.fg = fg
        self.bg = bg
        self.attrs = attrs
        self.width = width
    }
}

struct CursorFrame: Codable, Equatable {
    let row: Int
    let col: Int
    let visible: Bool
}

// ---- Frame variants ----

struct ScreenSnapshotFrame: Equatable {
    let seq: Int
    let rows: Int
    let cols: Int
    let cells: [[CellFrame]]
    let cursor: CursorFrame
    let title: String?
}

struct ScreenDeltaRow: Codable, Equatable {
    let row: Int
    let cells: [CellFrame]
}

struct ScreenDeltaFrame: Equatable {
    let seq: Int
    let rows: [ScreenDeltaRow]
    let cursor: CursorFrame?
    let title: String?
}

struct InputEventFrame: Equatable {
    let seq: Int
    /// Base64-encoded raw bytes.
    let bytes: String
}

struct ResizeFrame: Equatable {
    let seq: Int
    let rows: Int
    let cols: Int
}

struct TakeoverPingFrame: Equatable {
    let seq: Int
    let ts: Int
}

struct TakeoverByeFrame: Equatable {
    let seq: Int
    let reason: String?
}

// ---- Discriminated union ----

enum TakeoverFrame: Equatable {
    case screenSnapshot(ScreenSnapshotFrame)
    case screenDelta(ScreenDeltaFrame)
    case inputEvent(InputEventFrame)
    case resize(ResizeFrame)
    case ping(TakeoverPingFrame)
    case bye(TakeoverByeFrame)

    var kind: String {
        switch self {
        case .screenSnapshot: return "screen_snapshot"
        case .screenDelta:    return "screen_delta"
        case .inputEvent:     return "input_event"
        case .resize:         return "resize"
        case .ping:           return "ping"
        case .bye:            return "bye"
        }
    }
}

extension TakeoverFrame: Codable {
    private enum Kind: String, Codable {
        case screen_snapshot, screen_delta, input_event, resize, ping, bye
    }

    private enum CodingKeys: String, CodingKey {
        case kind, seq, rows, cols, cells, cursor, title, bytes, ts, reason, row
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        switch kind {
        case .screen_snapshot:
            self = .screenSnapshot(ScreenSnapshotFrame(
                seq:    try c.decode(Int.self, forKey: .seq),
                rows:   try c.decode(Int.self, forKey: .rows),
                cols:   try c.decode(Int.self, forKey: .cols),
                cells:  try c.decode([[CellFrame]].self, forKey: .cells),
                cursor: try c.decode(CursorFrame.self, forKey: .cursor),
                title:  try c.decodeIfPresent(String.self, forKey: .title)
            ))
        case .screen_delta:
            self = .screenDelta(ScreenDeltaFrame(
                seq:    try c.decode(Int.self, forKey: .seq),
                rows:   try c.decode([ScreenDeltaRow].self, forKey: .rows),
                cursor: try c.decodeIfPresent(CursorFrame.self, forKey: .cursor),
                title:  try c.decodeIfPresent(String.self, forKey: .title)
            ))
        case .input_event:
            self = .inputEvent(InputEventFrame(
                seq:   try c.decode(Int.self, forKey: .seq),
                bytes: try c.decode(String.self, forKey: .bytes)
            ))
        case .resize:
            self = .resize(ResizeFrame(
                seq:  try c.decode(Int.self, forKey: .seq),
                rows: try c.decode(Int.self, forKey: .rows),
                cols: try c.decode(Int.self, forKey: .cols)
            ))
        case .ping:
            self = .ping(TakeoverPingFrame(
                seq: try c.decode(Int.self, forKey: .seq),
                ts:  try c.decode(Int.self, forKey: .ts)
            ))
        case .bye:
            self = .bye(TakeoverByeFrame(
                seq:    try c.decode(Int.self, forKey: .seq),
                reason: try c.decodeIfPresent(String.self, forKey: .reason)
            ))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        switch self {
        case .screenSnapshot(let f):
            try c.encode(f.seq,    forKey: .seq)
            try c.encode(f.rows,   forKey: .rows)
            try c.encode(f.cols,   forKey: .cols)
            try c.encode(f.cells,  forKey: .cells)
            try c.encode(f.cursor, forKey: .cursor)
            try c.encodeIfPresent(f.title, forKey: .title)
        case .screenDelta(let f):
            try c.encode(f.seq,  forKey: .seq)
            try c.encode(f.rows, forKey: .rows)
            try c.encodeIfPresent(f.cursor, forKey: .cursor)
            try c.encodeIfPresent(f.title,  forKey: .title)
        case .inputEvent(let f):
            try c.encode(f.seq,   forKey: .seq)
            try c.encode(f.bytes, forKey: .bytes)
        case .resize(let f):
            try c.encode(f.seq,  forKey: .seq)
            try c.encode(f.rows, forKey: .rows)
            try c.encode(f.cols, forKey: .cols)
        case .ping(let f):
            try c.encode(f.seq, forKey: .seq)
            try c.encode(f.ts,  forKey: .ts)
        case .bye(let f):
            try c.encode(f.seq, forKey: .seq)
            try c.encodeIfPresent(f.reason, forKey: .reason)
        }
    }
}

// ---- Top-level encode / decode ----

enum TakeoverFrameCodec {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        // Keep the wire compact and stable — match the TS side which
        // calls JSON.stringify with no spaces.
        e.outputFormatting = [.withoutEscapingSlashes]
        return e
    }()
    static let decoder = JSONDecoder()

    static func encode(_ frame: TakeoverFrame) throws -> Data {
        try encoder.encode(frame)
    }

    static func decode(_ data: Data) throws -> TakeoverFrame {
        try decoder.decode(TakeoverFrame.self, from: data)
    }
}
