use super::style;
use crate::cli::PromptArgs;
use crate::config::CommandDurationModule;

pub fn render(cfg: &CommandDurationModule, args: &PromptArgs) -> Option<String> {
    let ms = (args.duration * 1000.0) as u64;
    if ms < cfg.min_time_ms {
        return None;
    }
    let formatted = format_duration(ms);
    Some(style::paint(&cfg.style, &format!("\u{f520} {formatted}"))) //
}

fn format_duration(ms: u64) -> String {
    if ms < 1000 {
        format!("{ms}ms")
    } else if ms < 60_000 {
        format!("{:.1}s", ms as f64 / 1000.0)
    } else if ms < 3_600_000 {
        let m = ms / 60_000;
        let s = (ms % 60_000) / 1000;
        format!("{m}m{s}s")
    } else {
        let h = ms / 3_600_000;
        let m = (ms % 3_600_000) / 60_000;
        format!("{h}h{m}m")
    }
}
