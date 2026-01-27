//! Voice notification system check command

use std::fs;
use std::path::PathBuf;

use super::notification_utils::hook_contains_notification_script;

/// Check if the voice notification system is installed
#[tauri::command]
pub fn check_notification_system() -> Result<bool, String> {
    let home = std::env::var("HOME").map_err(|_| "Could not get HOME directory")?;
    let settings_path = PathBuf::from(&home).join(".claude/settings.json");

    // Check if settings file exists and contains the notification hook
    if !settings_path.exists() {
        return Ok(false);
    }

    let content = fs::read_to_string(&settings_path)
        .map_err(|e| format!("Failed to read settings.json: {}", e))?;

    let settings: serde_json::Value = serde_json::from_str(&content)
        .map_err(|e| format!("Failed to parse settings.json: {}", e))?;

    // Check if hooks.Stop array contains notify-local-tts.sh
    if let Some(hooks) = settings.get("hooks") {
        if let Some(stop_hooks) = hooks.get("Stop") {
            if let Some(arr) = stop_hooks.as_array() {
                return Ok(arr.iter().any(hook_contains_notification_script));
            }
        }
    }

    Ok(false)
}
