use crate::config::TimeModule;

/// A5-1 stub: time module hides itself by default; real chrono-backed
/// rendering lands in A5-2 once the chrono dependency is added.
pub fn render(_cfg: &TimeModule) -> Option<String> {
    None
}
