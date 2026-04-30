//! Prompt segment renderers. Each module owns one logical chunk of the prompt
//! (cwd, git, duration, …) and reports its rendered string back to
//! `render::render`. Stub-shaped today (A5-1); real logic lands in A5-2.

pub mod character;
pub mod command_duration;
pub mod directory;
pub mod git_branch;
pub mod git_status;
pub mod status;
pub mod style;
pub mod time;
