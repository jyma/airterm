//! airprompt — AirTerm's native shell prompt renderer.
//!
//! On every keystroke `Enter` your shell calls `airprompt prompt --status=$? ...`,
//! which reads `~/.config/airterm/prompt.toml`, executes the configured modules
//! (cwd / git / time / …), and emits an ANSI + Nerd Font–styled line.

use anyhow::Result;
use clap::{Parser, Subcommand};

mod cli;
mod config;
mod modules;
mod render;
mod shell_init;

#[derive(Parser)]
#[command(name = "airprompt", version, about, long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Render the current prompt line. Called from a shell precmd hook.
    Prompt(cli::PromptArgs),

    /// Print the shell-init snippet so users can `eval "$(airprompt init zsh)"`.
    /// AirTerm injects this automatically via ZDOTDIR / --rcfile and never edits
    /// your dotfiles, so this is mostly for users running airprompt outside
    /// AirTerm or scripting their own integration.
    Init {
        /// Target shell. Currently `zsh` and `bash` are supported.
        shell: String,
    },
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    match cli.command {
        Command::Prompt(args) => {
            let cfg = config::PromptConfig::load_or_default()?;
            let line = render::render(&cfg, &args);
            // No trailing newline — the shell appends one when it prints PS1.
            print!("{line}");
        }
        Command::Init { shell } => {
            print!("{}", shell_init::script(&shell)?);
        }
    }
    Ok(())
}
