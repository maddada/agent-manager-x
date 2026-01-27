use std::process::Command;

/// Execute an AppleScript and return Ok if successful
pub fn execute_applescript(script: &str) -> Result<(), String> {
    let output = Command::new("osascript")
        .arg("-e")
        .arg(script)
        .output()
        .map_err(|e| format!("Failed to execute AppleScript: {}", e))?;

    if output.status.success() {
        let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
        // Check if script returned "found" - otherwise consider it a failure
        if stdout == "not found" {
            Err("Tab not found".to_string())
        } else {
            Ok(())
        }
    } else {
        let stderr = String::from_utf8_lossy(&output.stderr);
        Err(format!("AppleScript error: {}", stderr))
    }
}
