use super::style;
use crate::config::DirectoryModule;

/// A5-1 stub: returns a styled "~" placeholder so the rendered prompt looks
/// roughly correct while end-to-end wiring is verified. Real cwd truncation,
/// home-replacement, and git-root collapsing land in A5-2.
pub fn render(cfg: &DirectoryModule) -> Option<String> {
    Some(style::paint(&cfg.style, &cfg.home_symbol))
}
