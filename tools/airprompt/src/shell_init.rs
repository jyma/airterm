//! Shell-side glue. `airprompt init <shell>` prints a zsh / bash snippet
//! that wires precmd / preexec hooks so airprompt gets the previous command's
//! status and duration without the user editing their dotfiles.
//!
//! AirTerm sources this snippet automatically through ZDOTDIR (zsh) or
//! `--rcfile` (bash); end-users rarely run `airprompt init` themselves.

use anyhow::{anyhow, Result};

pub fn script(shell: &str) -> Result<String> {
    match shell {
        "zsh" => Ok(zsh()),
        "bash" => Ok(bash()),
        other => Err(anyhow!("unsupported shell: {other} (expected zsh|bash)")),
    }
}

/// zsh path uses `add-zsh-hook` + `zsh/datetime`'s `$EPOCHREALTIME` for
/// sub-second command timing — both shipped with every modern zsh build.
fn zsh() -> String {
    r#"# airprompt zsh integration — sourced by AirTerm at PTY start.
# Nothing here writes back to your dotfiles; uninstall by removing the
# AirTerm-managed ZDOTDIR override (or set [shell] inject_prompt=false in
# ~/.config/airterm/config.toml).

zmodload -F zsh/datetime b:strftime b:zselect

typeset -F _AIRPROMPT_CMD_START

_airprompt_preexec() {
    _AIRPROMPT_CMD_START=$EPOCHREALTIME
}

_airprompt_precmd() {
    local _ap_status=$?
    local _ap_duration=0
    if [[ -n "$_AIRPROMPT_CMD_START" ]]; then
        _ap_duration=$(( EPOCHREALTIME - _AIRPROMPT_CMD_START ))
        _AIRPROMPT_CMD_START=
    fi
    PROMPT="$(airprompt prompt --status=$_ap_status --duration=$_ap_duration)"
}

# Yield to a user prompt that's already been deliberately set up. This lets
# starship / p10k / oh-my-zsh users keep their existing setup even with
# AirTerm's auto-injection turned on.
_airprompt_should_install() {
    [[ "$PROMPT" == *'starship_'* ]] && return 1
    [[ -n "$STARSHIP_SHELL" ]] && return 1
    [[ -n "$POWERLEVEL9K_MODE" ]] && return 1
    [[ -n "$ZSH" && -d "$ZSH/oh-my-zsh.sh" ]] && return 1
    return 0
}

if _airprompt_should_install; then
    autoload -Uz add-zsh-hook
    add-zsh-hook preexec _airprompt_preexec
    add-zsh-hook precmd  _airprompt_precmd
fi
"#
        .to_string()
}

/// bash path. macOS's stock `/bin/bash` is 3.2 (2007) and lacks the
/// `$EPOCHREALTIME` builtin and `$SECONDS` floats — that user gets a
/// duration of 0. brew bash 5+ users get full sub-second timing.
fn bash() -> String {
    r#"# airprompt bash integration — sourced by AirTerm at PTY start.
# Bash 5+ provides $EPOCHREALTIME for sub-second timing; older bash falls
# back to $SECONDS (whole-second resolution).

_AIRPROMPT_CMD_START=

_airprompt_debug() {
    [[ -n "$COMP_LINE" ]] && return  # ignore tab-completion subshells
    [[ "$BASH_COMMAND" == _airprompt_* ]] && return
    if [[ -z "$_AIRPROMPT_CMD_START" ]]; then
        if [[ -n "$EPOCHREALTIME" ]]; then
            _AIRPROMPT_CMD_START=$EPOCHREALTIME
        else
            _AIRPROMPT_CMD_START=$SECONDS
        fi
    fi
}

_airprompt_prompt_command() {
    local _ap_status=$?
    local _ap_duration=0
    if [[ -n "$_AIRPROMPT_CMD_START" ]]; then
        if [[ -n "$EPOCHREALTIME" ]]; then
            _ap_duration=$(awk "BEGIN{print $EPOCHREALTIME - $_AIRPROMPT_CMD_START}")
        else
            _ap_duration=$(( SECONDS - _AIRPROMPT_CMD_START ))
        fi
        _AIRPROMPT_CMD_START=
    fi
    PS1="$(airprompt prompt --status=$_ap_status --duration=$_ap_duration)"
}

_airprompt_should_install() {
    [[ -n "$STARSHIP_SHELL" ]] && return 1
    [[ "$PS1" == *'powerline'* ]] && return 1
    return 0
}

if _airprompt_should_install; then
    trap '_airprompt_debug' DEBUG
    PROMPT_COMMAND="_airprompt_prompt_command${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
fi
"#
        .to_string()
}
