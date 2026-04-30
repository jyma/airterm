use super::style;
use crate::config::DirectoryModule;
use std::path::{Component, PathBuf};

/// Renders the current working directory:
///   1. replace `$HOME` prefix with the configured `home_symbol` (default `~`)
///   2. truncate the path to its last `truncation_length` components
///   3. join with `/` and apply the configured style
///
/// Returns `None` only if `current_dir()` itself fails (chmod 000, deleted
/// directory, etc.) — in that case the prompt skips this segment instead of
/// printing a confusing error.
pub fn render(cfg: &DirectoryModule) -> Option<String> {
    let cwd = std::env::current_dir().ok()?;
    let home = dirs::home_dir();

    // Replace home prefix.
    let display: PathBuf = match home.as_deref() {
        Some(h) if cwd.starts_with(h) => {
            let rest = cwd.strip_prefix(h).ok()?;
            let mut p = PathBuf::from(&cfg.home_symbol);
            p.push(rest);
            p
        }
        _ => cwd,
    };

    let truncated = truncate(&display, cfg.truncation_length);
    Some(style::paint(&cfg.style, &truncated))
}

fn truncate(path: &std::path::Path, keep_last: usize) -> String {
    if keep_last == 0 {
        return path.display().to_string();
    }
    // Collect non-root components so we can keep the trailing N. Root prefix
    // ("/") is preserved by adding it back when the original path was absolute.
    let comps: Vec<String> = path
        .components()
        .filter_map(|c| match c {
            Component::Normal(s) => s.to_str().map(String::from),
            Component::CurDir => Some(".".into()),
            Component::ParentDir => Some("..".into()),
            // skip root / prefix — re-applied below if path is absolute
            _ => None,
        })
        .collect();

    if comps.is_empty() {
        return path.display().to_string();
    }

    let total = comps.len();
    let start = total.saturating_sub(keep_last);
    let mut out = String::new();
    if start > 0 {
        // Mark omission so the user can tell that we trimmed the head.
        out.push('…');
        out.push('/');
    } else if path.is_absolute() && !path.starts_with("~") {
        out.push('/');
    }
    out.push_str(&comps[start..].join("/"));
    out
}
