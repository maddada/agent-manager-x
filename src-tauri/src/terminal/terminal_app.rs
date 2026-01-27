use super::applescript::execute_applescript;

/// Focus Terminal.app tab by TTY
pub fn focus_terminal_app_by_tty(tty: &str) -> Result<(), String> {
    // Check if Terminal is running first
    let check_script = r#"
        tell application "System Events"
            return exists process "Terminal"
        end tell
    "#;

    let check_output = std::process::Command::new("osascript")
        .arg("-e")
        .arg(check_script)
        .output()
        .map_err(|e| format!("Failed to check Terminal: {}", e))?;

    let is_running = String::from_utf8_lossy(&check_output.stdout).trim() == "true";
    if !is_running {
        return Err("Terminal is not running".to_string());
    }

    let script = format!(r#"
        tell application "Terminal"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    try
                        if tty of t contains "{}" then
                            set selected of t to true
                            set index of w to 1
                            return "found"
                        end if
                    end try
                end repeat
            end repeat
        end tell
        return "not found"
    "#, tty);

    execute_applescript(&script)
}
