use std::process::Command;
use super::applescript::execute_applescript;
use super::iterm;
use super::terminal_app;

/// Focus a tmux pane by matching its TTY
/// Returns Ok if the pane was found and focused, Err otherwise
pub fn focus_tmux_pane_by_tty(tty: &str) -> Result<(), String> {
    // Check if tmux is running by listing panes
    let output = Command::new("tmux")
        .args(["list-panes", "-a", "-F", "#{pane_tty} #{session_name}:#{window_index}.#{pane_index}"])
        .output()
        .map_err(|e| format!("Failed to run tmux: {}", e))?;

    if !output.status.success() {
        return Err("tmux not running or no sessions".to_string());
    }

    let panes = String::from_utf8_lossy(&output.stdout);

    // Find the pane with matching TTY
    // TTY from ps is like "ttys003", tmux returns "/dev/ttys003"
    for line in panes.lines() {
        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.len() >= 2 {
            let pane_tty = parts[0];
            let target = parts[1];

            // Match TTY (handle both with and without /dev/ prefix)
            if pane_tty.contains(tty) || pane_tty.ends_with(tty) {
                // Select the window and pane in tmux
                let _ = Command::new("tmux")
                    .args(["select-window", "-t", target])
                    .output();

                let _ = Command::new("tmux")
                    .args(["select-pane", "-t", target])
                    .output();

                // Now we need to focus the terminal app that's running tmux
                // Try to find and focus it
                focus_tmux_client_terminal()?;

                return Ok(());
            }
        }
    }

    Err("Pane not found in tmux".to_string())
}

/// Focus the terminal application that is running the tmux client
fn focus_tmux_client_terminal() -> Result<(), String> {
    // Get the tmux client TTY
    let output = Command::new("tmux")
        .args(["display-message", "-p", "#{client_tty}"])
        .output()
        .map_err(|e| format!("Failed to get tmux client tty: {}", e))?;

    if !output.status.success() {
        // No active client, try to activate any terminal with tmux
        return focus_any_terminal_with_tmux();
    }

    let client_tty = String::from_utf8_lossy(&output.stdout).trim().to_string();

    if client_tty.is_empty() {
        return focus_any_terminal_with_tmux();
    }

    // Extract just the tty name (e.g., "ttys003" from "/dev/ttys003")
    let tty_name = client_tty.split('/').last().unwrap_or(&client_tty);

    // Try to focus the terminal running this TTY
    if iterm::focus_iterm_by_tty(tty_name).is_ok() {
        return Ok(());
    }

    if terminal_app::focus_terminal_app_by_tty(tty_name).is_ok() {
        return Ok(());
    }

    // Last resort: just activate any terminal that might be running tmux
    focus_any_terminal_with_tmux()
}

/// Fallback: Focus any terminal app that might be running tmux
fn focus_any_terminal_with_tmux() -> Result<(), String> {
    // Try iTerm2 first, then Terminal.app
    let script = r#"
        tell application "System Events"
            if exists process "iTerm2" then
                tell application "iTerm2" to activate
                return "found"
            else if exists process "Terminal" then
                tell application "Terminal" to activate
                return "found"
            end if
        end tell
        return "not found"
    "#;

    execute_applescript(script)
}
