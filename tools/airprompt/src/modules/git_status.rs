use super::style;
use crate::config::GitStatusModule;
use git2::{Repository, Status, StatusOptions};

/// Renders the dirty / ahead / behind summary for the current repo. Hidden
/// when the working tree is clean and HEAD is in sync with its upstream.
pub fn render(cfg: &GitStatusModule) -> Option<String> {
    let repo = Repository::discover(std::env::current_dir().ok()?).ok()?;

    let mut opts = StatusOptions::new();
    opts.include_untracked(true).renames_head_to_index(true);
    let statuses = repo.statuses(Some(&mut opts)).ok()?;

    let dirty = statuses.iter().any(|s| {
        let st = s.status();
        st.intersects(
            Status::INDEX_NEW
                | Status::INDEX_MODIFIED
                | Status::INDEX_DELETED
                | Status::INDEX_RENAMED
                | Status::INDEX_TYPECHANGE
                | Status::WT_NEW
                | Status::WT_MODIFIED
                | Status::WT_DELETED
                | Status::WT_RENAMED
                | Status::WT_TYPECHANGE,
        )
    });

    let (ahead, behind) = ahead_behind(&repo).unwrap_or((0, 0));

    if !dirty && ahead == 0 && behind == 0 {
        return None;
    }

    let mut parts = String::new();
    if dirty {
        parts.push_str(&cfg.modified);
    }
    if ahead > 0 {
        if !parts.is_empty() { parts.push(' '); }
        parts.push_str(&format!("{}{ahead}", cfg.ahead));
    }
    if behind > 0 {
        if !parts.is_empty() { parts.push(' '); }
        parts.push_str(&format!("{}{behind}", cfg.behind));
    }
    Some(style::paint(&cfg.style, &parts))
}

fn ahead_behind(repo: &Repository) -> Option<(usize, usize)> {
    let head = repo.head().ok()?;
    let local_oid = head.target()?;
    let branch_name = head.shorthand()?;
    let upstream = repo
        .find_branch(branch_name, git2::BranchType::Local)
        .ok()?
        .upstream()
        .ok()?;
    let upstream_oid = upstream.get().target()?;
    repo.graph_ahead_behind(local_oid, upstream_oid).ok()
}
