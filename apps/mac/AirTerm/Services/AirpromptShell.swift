import Foundation

/// Runtime scaffolding that lets a freshly forked zsh/bash PTY pick up
/// airprompt without ever touching `~/.zshrc`. We:
///
///   1. Locate the bundled `airprompt` binary (Resources/bin/airprompt).
///   2. Materialize a per-user shell init dir in
///      `~/Library/Application Support/AirTerm/shell/` containing a
///      `.zshrc` shim that sources the user's real zshrc and then
///      `eval`s `airprompt init zsh`.
///   3. Hand the PTY a `ZDOTDIR` override pointing at that dir, plus a
///      `PATH` prepend so `airprompt` resolves without an absolute path
///      inside the user's PROMPT command substitution.
///
/// Returns nil when the airprompt binary isn't found (dev `swift run`
/// before `bundle.sh`, broken install). Callers fall back to no prompt
/// injection — the user keeps whatever PS1 they had.
enum AirpromptShell {
    struct Scaffolding {
        let zdotdir: URL
        let binDir: URL
    }

    static func prepareScaffolding() -> Scaffolding? {
        guard let bin = locateBinary() else {
            DebugLog.log("AirpromptShell: airprompt binary not found in bundle")
            return nil
        }
        let binDir = bin.deletingLastPathComponent()

        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else {
            return nil
        }
        let zdotdir = appSupport.appendingPathComponent("AirTerm/shell")
        try? FileManager.default.createDirectory(
            at: zdotdir, withIntermediateDirectories: true
        )

        writeZshShim(zdotdir: zdotdir, airpromptBin: bin)
        writeBashShim(zdotdir: zdotdir, airpromptBin: bin)
        return Scaffolding(zdotdir: zdotdir, binDir: binDir)
    }

    private static func locateBinary() -> URL? {
        // Production: AirTerm.app/Contents/Resources/bin/airprompt.
        let bundleBin = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/bin/airprompt")
        if FileManager.default.isExecutableFile(atPath: bundleBin.path) {
            return bundleBin
        }
        return nil
    }

    /// bash equivalent of the zsh shim. PTY launches `bash --rcfile <this>`,
    /// which forces bash into non-login interactive mode (the only mode that
    /// honours `--rcfile`); the shim sources `~/.bash_profile` and
    /// `~/.bashrc` itself to recover the login-shell side effects (brew
    /// PATH, nvm init, etc.) the dropped `-l` would have run.
    private static func writeBashShim(zdotdir: URL, airpromptBin: URL) {
        let bashrc = """
        # AirTerm-managed bash init. Auto-generated each launch; edits here
        # are overwritten. Disable in ~/.config/airterm/config.toml:
        #   [shell]
        #   inject_prompt = false

        # Recover login-shell behaviour the dropped -l would have run.
        [[ -f "$HOME/.bash_profile" ]] && source "$HOME/.bash_profile"
        [[ -f "$HOME/.bashrc" ]] && source "$HOME/.bashrc"

        eval "$(\(airpromptBin.path) init bash)"
        """
        let bashrcURL = zdotdir.appendingPathComponent(".bashrc")
        try? bashrc.write(to: bashrcURL, atomically: true, encoding: .utf8)
    }

    /// Re-written every launch so a rebuilt airprompt at a new path picks up
    /// immediately — keeps dev/prod path swaps coherent without manual cleanup.
    private static func writeZshShim(zdotdir: URL, airpromptBin: URL) {
        let zshrc = """
        # AirTerm-managed zsh init. Auto-generated each launch; edits here are
        # overwritten. Disable in ~/.config/airterm/config.toml:
        #   [shell]
        #   inject_prompt = false

        # Source the user's normal zshrc first so existing aliases and
        # functions are available to airprompt's hooks. The prompt setup at
        # the bottom respects starship / p10k / oh-my-zsh users (see
        # _airprompt_should_install).
        [[ -f "$HOME/.zshrc" ]] && source "$HOME/.zshrc"

        eval "$(\(airpromptBin.path) init zsh)"
        """
        let zshrcURL = zdotdir.appendingPathComponent(".zshrc")
        try? zshrc.write(to: zshrcURL, atomically: true, encoding: .utf8)
    }
}
