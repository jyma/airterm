use super::style;
use crate::config::TimeModule;
use chrono::Local;

pub fn render(cfg: &TimeModule) -> Option<String> {
    if cfg.disabled {
        return None;
    }
    let formatted = Local::now().format(&cfg.format).to_string();
    Some(style::paint(&cfg.style, &formatted))
}
