//! Top-level prompt assembly. Walks `config.format`, asks each module for its
//! rendered segment, joins them with single spaces, and adds the trailing
//! character on its own line.
//!
//! Modules return `None` when they have nothing relevant to show (clean git
//! state, command duration below threshold, etc.) so the prompt stays compact.

use crate::cli::PromptArgs;
use crate::config::PromptConfig;
use crate::modules;

pub fn render(cfg: &PromptConfig, args: &PromptArgs) -> String {
    let mut segments: Vec<String> = Vec::with_capacity(cfg.format.len());

    for name in &cfg.format {
        if let Some(seg) = render_module(name, cfg, args) {
            if !seg.is_empty() {
                segments.push(seg);
            }
        }
    }

    let line = segments.join(" ");
    // Character module renders on its own line so users get a clean
    // `❯ ` indent at the cursor regardless of how many segments precede it.
    let character = modules::character::render(&cfg.character, args);
    if line.is_empty() {
        format!("{character} ")
    } else {
        format!("{line}\n{character} ")
    }
}

fn render_module(name: &str, cfg: &PromptConfig, args: &PromptArgs) -> Option<String> {
    match name {
        "directory" => modules::directory::render(&cfg.directory),
        "git_branch" => modules::git_branch::render(&cfg.git_branch),
        "git_status" => modules::git_status::render(&cfg.git_status),
        "command_duration" => modules::command_duration::render(&cfg.command_duration, args),
        "status" => modules::status::render(&cfg.status, args),
        "time" => modules::time::render(&cfg.time),
        "character" => None, // rendered on its own line, see above
        _ => None,
    }
}
