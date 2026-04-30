use super::style;
use crate::cli::PromptArgs;
use crate::config::StatusModule;

pub fn render(cfg: &StatusModule, args: &PromptArgs) -> Option<String> {
    if args.status == 0 {
        return None;
    }
    Some(style::paint(&cfg.style, &format!("✘ {}", args.status)))
}
