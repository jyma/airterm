use clap::Args;

/// Inputs the shell hook supplies for each prompt render. All optional so a
/// user can wire airprompt up incrementally — missing values just suppress
/// their corresponding modules.
#[derive(Args, Debug, Clone, Default)]
pub struct PromptArgs {
    /// Exit status of the previous foreground command. Used by the `status`
    /// and `character` modules.
    #[arg(long, default_value_t = 0)]
    pub status: i32,

    /// Wall-clock duration (in seconds, fractional) of the previous foreground
    /// command. The `command_duration` module hides itself when this is below
    /// its `min_time` threshold.
    #[arg(long, default_value_t = 0.0)]
    pub duration: f64,
}
