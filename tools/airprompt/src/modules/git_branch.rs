use crate::config::GitBranchModule;

/// A5-1 stub: hidden until A5-2 wires up libgit2 to read .git/HEAD.
pub fn render(_cfg: &GitBranchModule) -> Option<String> {
    None
}
