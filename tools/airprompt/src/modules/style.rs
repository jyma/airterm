//! Tiny ANSI styling helper. Translates starship-ish style strings
//! ("bold red", "purple", "italic blue") into the surrounding SGR escapes.
//! Doing this in-house (instead of pulling in `nu-ansi-term` / `crossterm`)
//! keeps the binary small and the cold start fast.

/// Wraps `text` in SGR escapes derived from `spec`. An empty / unknown spec
/// returns `text` unchanged so misconfigured users still get something
/// readable instead of a panic.
pub fn paint(spec: &str, text: &str) -> String {
    let mut codes: Vec<&str> = Vec::new();
    for word in spec.split_whitespace() {
        match word {
            "bold" => codes.push("1"),
            "dim" => codes.push("2"),
            "italic" => codes.push("3"),
            "underline" => codes.push("4"),
            "reverse" => codes.push("7"),
            "black" => codes.push("30"),
            "red" => codes.push("31"),
            "green" => codes.push("32"),
            "yellow" => codes.push("33"),
            "blue" => codes.push("34"),
            "purple" | "magenta" => codes.push("35"),
            "cyan" => codes.push("36"),
            "white" => codes.push("37"),
            _ => {}
        }
    }
    if codes.is_empty() {
        return text.to_string();
    }
    let prefix = codes.join(";");
    format!("\x1b[{prefix}m{text}\x1b[0m")
}
