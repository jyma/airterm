use super::style;
use crate::config::GitBranchModule;
use git2::Repository;

/// Renders the current git branch name (or short commit hash when HEAD is
/// detached). Hidden when cwd is not inside a git repository, which is the
/// expected case for ~half of all prompts.
pub fn render(cfg: &GitBranchModule) -> Option<String> {
    let repo = Repository::discover(std::env::current_dir().ok()?).ok()?;
    let head = repo.head().ok()?;
    let name = if let Some(short) = head.shorthand() {
        short.to_string()
    } else {
        // Detached HEAD: fall back to a 7-char SHA.
        let oid = head.target()?;
        oid.to_string().chars().take(7).collect()
    };
    Some(style::paint(&cfg.style, &format!("{}{}", cfg.symbol, name)))
}
