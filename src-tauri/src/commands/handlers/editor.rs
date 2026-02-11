//! Editor and terminal command handlers

use std::process::Command;

/// Get the full PATH from the user's login shell.
/// Bundled macOS apps inherit a minimal PATH (/usr/bin:/bin:/usr/sbin:/sbin),
/// so editor CLIs installed via Homebrew or app installers won't be found.
/// We resolve this by asking the login shell for its PATH, with static extras as fallback.
fn enriched_path() -> String {
    // Try to get the full PATH from the user's default login shell
    if let Ok(output) = Command::new("/bin/zsh")
        .args(["-l", "-c", "echo $PATH"])
        .output()
    {
        let shell_path = String::from_utf8_lossy(&output.stdout).trim().to_string();
        if !shell_path.is_empty() {
            return shell_path;
        }
    }

    // Fallback: prepend common locations to the current PATH
    let base = std::env::var("PATH").unwrap_or_default();
    let home = std::env::var("HOME").unwrap_or_default();
    let mut parts = vec![
        "/usr/local/bin".to_string(),
        "/opt/homebrew/bin".to_string(),
        "/opt/homebrew/sbin".to_string(),
    ];
    if !home.is_empty() {
        parts.push(format!("{}/.local/bin", home));
    }
    if !base.is_empty() {
        parts.push(base);
    }
    parts.join(":")
}

/// Open a project path in an editor
#[tauri::command]
pub fn open_in_editor(path: String, editor: String) -> Result<(), String> {
    // Map known editor names to their CLI commands, or use the editor string directly for custom commands
    let cmd = match editor.as_str() {
        "zed" => "zed",
        "code" => "code",
        "cursor" => "cursor",
        "sublime" => "subl",
        "neovim" => "nvim",
        "webstorm" => "webstorm",
        "idea" => "idea",
        custom => custom, // Use the provided string directly for custom editors
    };

    Command::new(cmd)
        .arg(&path)
        .env("PATH", enriched_path())
        .spawn()
        .map_err(|e| format!("Failed to open {} in {}: {}", path, editor, e))?;

    Ok(())
}

/// Open a project path in a terminal
#[tauri::command]
pub fn open_in_terminal(path: String, terminal: String) -> Result<(), String> {
    match terminal.as_str() {
        "ghostty" => {
            Command::new("open")
                .args(["-a", "Ghostty", &path])
                .spawn()
                .map_err(|e| format!("Failed to open Ghostty: {}", e))?;
        }
        "iterm" => {
            // iTerm2 uses AppleScript to open in a specific directory
            let script = format!(
                r#"tell application "iTerm"
                    activate
                    create window with default profile
                    tell current session of current window
                        write text "cd '{}'"
                    end tell
                end tell"#,
                path.replace("'", "'\\''")
            );
            Command::new("osascript")
                .args(["-e", &script])
                .spawn()
                .map_err(|e| format!("Failed to open iTerm2: {}", e))?;
        }
        "kitty" => {
            Command::new("kitty")
                .args(["--directory", &path])
                .env("PATH", enriched_path())
                .spawn()
                .map_err(|e| format!("Failed to open Kitty: {}", e))?;
        }
        "terminal" => {
            // macOS Terminal.app
            let script = format!(
                r#"tell application "Terminal"
                    activate
                    do script "cd '{}'"
                end tell"#,
                path.replace("'", "'\\''")
            );
            Command::new("osascript")
                .args(["-e", &script])
                .spawn()
                .map_err(|e| format!("Failed to open Terminal: {}", e))?;
        }
        "warp" => {
            Command::new("open")
                .args(["-a", "Warp", &path])
                .spawn()
                .map_err(|e| format!("Failed to open Warp: {}", e))?;
        }
        "alacritty" => {
            Command::new("alacritty")
                .args(["--working-directory", &path])
                .env("PATH", enriched_path())
                .spawn()
                .map_err(|e| format!("Failed to open Alacritty: {}", e))?;
        }
        "hyper" => {
            Command::new("open")
                .args(["-a", "Hyper", &path])
                .spawn()
                .map_err(|e| format!("Failed to open Hyper: {}", e))?;
        }
        custom => {
            // Try to open as a macOS app first, then fall back to command with path argument
            let app_result = Command::new("open").args(["-a", custom, &path]).spawn();

            if app_result.is_err() {
                // Fall back to running the command directly with path as argument
                Command::new(custom)
                    .arg(&path)
                    .env("PATH", enriched_path())
                    .spawn()
                    .map_err(|e| format!("Failed to open {}: {}", custom, e))?;
            }
        }
    }

    Ok(())
}
