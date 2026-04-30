use anyhow::Result;
use serde::Deserialize;
use std::path::PathBuf;

/// Top-level prompt config. Mirrors the rough shape of starship.toml so
/// existing presets translate naturally, but only declares the modules
/// airprompt actually ships.
#[derive(Debug, Clone, Deserialize)]
#[serde(default)]
pub struct PromptConfig {
    /// Module ordering in the rendered prompt. Defaults to a sane Starship-ish
    /// default. Anything not in this list is omitted.
    pub format: Vec<String>,

    pub directory: DirectoryModule,
    pub git_branch: GitBranchModule,
    pub git_status: GitStatusModule,
    pub command_duration: CommandDurationModule,
    pub status: StatusModule,
    pub time: TimeModule,
    pub character: CharacterModule,
}

impl Default for PromptConfig {
    fn default() -> Self {
        Self {
            format: vec![
                "directory".into(),
                "git_branch".into(),
                "git_status".into(),
                "command_duration".into(),
                "status".into(),
                "character".into(),
            ],
            directory: DirectoryModule::default(),
            git_branch: GitBranchModule::default(),
            git_status: GitStatusModule::default(),
            command_duration: CommandDurationModule::default(),
            status: StatusModule::default(),
            time: TimeModule::default(),
            character: CharacterModule::default(),
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(default)]
pub struct DirectoryModule {
    pub truncation_length: usize,
    pub style: String,
    pub home_symbol: String,
}
impl Default for DirectoryModule {
    fn default() -> Self {
        Self {
            truncation_length: 3,
            style: "bold cyan".into(),
            home_symbol: "~".into(),
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(default)]
pub struct GitBranchModule {
    pub symbol: String,
    pub style: String,
}
impl Default for GitBranchModule {
    fn default() -> Self {
        Self {
            symbol: "\u{e0a0} ".into(), // powerline branch
            style: "bold purple".into(),
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(default)]
pub struct GitStatusModule {
    pub modified: String,
    pub ahead: String,
    pub behind: String,
    pub style: String,
}
impl Default for GitStatusModule {
    fn default() -> Self {
        Self {
            modified: "*".into(),
            ahead: "\u{21e1}".into(), // ⇡
            behind: "\u{21e3}".into(), // ⇣
            style: "yellow".into(),
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(default)]
pub struct CommandDurationModule {
    /// Hide the duration unless the previous command ran longer than this
    /// many milliseconds. Mirrors starship's `min_time`.
    pub min_time_ms: u64,
    pub style: String,
}
impl Default for CommandDurationModule {
    fn default() -> Self {
        Self {
            min_time_ms: 2000,
            style: "yellow".into(),
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(default)]
pub struct StatusModule {
    /// Render only when status != 0.
    pub style: String,
}
impl Default for StatusModule {
    fn default() -> Self {
        Self {
            style: "bold red".into(),
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(default)]
pub struct TimeModule {
    pub disabled: bool,
    pub format: String,
    pub style: String,
}
impl Default for TimeModule {
    fn default() -> Self {
        Self {
            disabled: true,
            format: "%H:%M".into(),
            style: "white".into(),
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(default)]
pub struct CharacterModule {
    pub success: String,
    pub error: String,
    pub success_style: String,
    pub error_style: String,
}
impl Default for CharacterModule {
    fn default() -> Self {
        Self {
            success: "\u{276f}".into(), // ❯
            error: "\u{276f}".into(),
            success_style: "green".into(),
            error_style: "red".into(),
        }
    }
}

impl PromptConfig {
    /// Resolves config from `~/.config/airterm/prompt.toml`. Missing file or
    /// parse failure both return defaults — the prompt should never crash a
    /// shell session, ever.
    pub fn load_or_default() -> Result<Self> {
        let Some(path) = config_path() else {
            return Ok(Self::default());
        };
        if !path.exists() {
            return Ok(Self::default());
        }
        let text = std::fs::read_to_string(&path)?;
        match toml::from_str::<Self>(&text) {
            Ok(cfg) => Ok(cfg),
            Err(_) => Ok(Self::default()),
        }
    }
}

fn config_path() -> Option<PathBuf> {
    dirs::home_dir().map(|h| h.join(".config/airterm/prompt.toml"))
}
