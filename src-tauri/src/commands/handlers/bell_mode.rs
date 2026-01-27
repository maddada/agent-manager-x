//! Bell mode notification command handlers

use std::fs;
use std::path::PathBuf;

use super::notification_scripts::{NOTIFICATION_SCRIPT, NOTIFICATION_SCRIPT_BELL};

/// Check if bell mode is enabled (script uses bell instead of TTS)
#[tauri::command]
pub fn check_bell_mode() -> Result<bool, String> {
    let home = std::env::var("HOME").map_err(|_| "Could not get HOME directory")?;
    let script_path = PathBuf::from(&home).join(".claude/hooks/notify-local-tts.sh");

    if !script_path.exists() {
        return Ok(false);
    }

    let content =
        fs::read_to_string(&script_path).map_err(|e| format!("Failed to read script: {}", e))?;

    // Check if script contains afplay (bell mode) instead of say (TTS mode)
    Ok(content.contains("afplay") && !content.contains("say \"$SUMMARY\""))
}

/// Set bell mode (modify script to use bell or TTS)
#[tauri::command]
pub fn set_bell_mode(enabled: bool) -> Result<(), String> {
    use std::os::unix::fs::PermissionsExt;

    let home = std::env::var("HOME").map_err(|_| "Could not get HOME directory")?;
    let script_path = PathBuf::from(&home).join(".claude/hooks/notify-local-tts.sh");

    if !script_path.exists() {
        return Err("Notification system not installed".to_string());
    }

    // Write the appropriate script
    let script_content = if enabled {
        NOTIFICATION_SCRIPT_BELL
    } else {
        NOTIFICATION_SCRIPT
    };

    fs::write(&script_path, script_content)
        .map_err(|e| format!("Failed to write script: {}", e))?;

    // Ensure executable
    let mut perms = fs::metadata(&script_path)
        .map_err(|e| format!("Failed to get script metadata: {}", e))?
        .permissions();
    perms.set_mode(0o755);
    fs::set_permissions(&script_path, perms)
        .map_err(|e| format!("Failed to set script permissions: {}", e))?;

    Ok(())
}
