//! Voice notification system uninstallation command

use std::fs;
use std::path::PathBuf;

use super::notification_utils::hook_contains_notification_script;

/// Uninstall the voice notification system
#[tauri::command]
pub fn uninstall_notification_system() -> Result<(), String> {
    let home = std::env::var("HOME").map_err(|_| "Could not get HOME directory")?;
    let claude_dir = PathBuf::from(&home).join(".claude");
    let script_path = claude_dir.join("hooks/notify-local-tts.sh");
    let settings_path = claude_dir.join("settings.json");
    let claude_md_path = claude_dir.join("CLAUDE.md");

    // 1. Remove the Stop hook from settings.json
    if settings_path.exists() {
        let content = fs::read_to_string(&settings_path)
            .map_err(|e| format!("Failed to read settings.json: {}", e))?;

        let mut settings: serde_json::Value = serde_json::from_str(&content)
            .map_err(|e| format!("Failed to parse settings.json: {}", e))?;

        if let Some(hooks) = settings.get_mut("hooks") {
            if let Some(stop_hooks) = hooks.get_mut("Stop") {
                if let Some(arr) = stop_hooks.as_array_mut() {
                    // Remove entries containing notify-local-tts.sh
                    arr.retain(|entry| !hook_contains_notification_script(entry));
                }
            }
        }

        let settings_str = serde_json::to_string_pretty(&settings)
            .map_err(|e| format!("Failed to serialize settings: {}", e))?;
        fs::write(&settings_path, settings_str)
            .map_err(|e| format!("Failed to write settings.json: {}", e))?;
    }

    // 2. Remove Voice Notifications section from CLAUDE.md
    if claude_md_path.exists() {
        let content = fs::read_to_string(&claude_md_path)
            .map_err(|e| format!("Failed to read CLAUDE.md: {}", e))?;

        // Remove the Voice Notifications section
        let section_start = "## Voice Notifications";
        if let Some(start_idx) = content.find(section_start) {
            // Find the next ## heading or end of file
            let after_section = &content[start_idx + section_start.len()..];
            let end_offset = after_section
                .find("\n## ")
                .map(|i| start_idx + section_start.len() + i)
                .unwrap_or(content.len());

            // Also check for leading newlines before the section
            let actual_start = content[..start_idx]
                .rfind(|c: char| c != '\n')
                .map(|i| i + 1)
                .unwrap_or(start_idx);

            let new_content = format!("{}{}", &content[..actual_start], &content[end_offset..]);
            fs::write(&claude_md_path, new_content)
                .map_err(|e| format!("Failed to write CLAUDE.md: {}", e))?;
        }
    }

    // 3. Delete the script file
    if script_path.exists() {
        fs::remove_file(&script_path).map_err(|e| format!("Failed to delete script: {}", e))?;
    }

    Ok(())
}
