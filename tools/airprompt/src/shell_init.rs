//! Stubs for `airprompt init <shell>`. A5-1 returns a banner so the wiring is
//! verifiable; A7 fills these in with real precmd hooks + PS1 templates.

use anyhow::{anyhow, Result};

pub fn script(shell: &str) -> Result<String> {
    match shell {
        "zsh" => Ok(stub_zsh()),
        "bash" => Ok(stub_bash()),
        other => Err(anyhow!("unsupported shell: {other} (expected zsh|bash)")),
    }
}

fn stub_zsh() -> String {
    // Real precmd / preexec hooks land in A7.
    "# airprompt zsh init (stub — see A7 for full hook wiring)\n\
     PS1='$(airprompt prompt --status=$? --duration=0)'\n"
        .into()
}

fn stub_bash() -> String {
    "# airprompt bash init (stub — see A7 for full hook wiring)\n\
     PS1='$(airprompt prompt --status=$? --duration=0)'\n"
        .into()
}
