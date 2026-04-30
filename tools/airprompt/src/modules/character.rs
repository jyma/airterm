use super::style;
use crate::cli::PromptArgs;
use crate::config::CharacterModule;

pub fn render(cfg: &CharacterModule, args: &PromptArgs) -> String {
    if args.status == 0 {
        style::paint(&cfg.success_style, &cfg.success)
    } else {
        style::paint(&cfg.error_style, &cfg.error)
    }
}
