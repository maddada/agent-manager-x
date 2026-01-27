//! Voice notification system installation command

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::PathBuf;

use super::notification_scripts::{CLAUDE_MD_VOICE_SECTION, NOTIFICATION_SCRIPT};
use super::notification_utils::hook_contains_notification_script;

/// Install the voice notification system
#[tauri::command]
pub fn install_notification_system() -> Result<(), String> {
    let home = std::env::var("HOME").map_err(|_| "Could not get HOME directory")?;
    let claude_dir = PathBuf::from(&home).join(".claude");
    let hooks_dir = claude_dir.join("hooks");
    let script_path = hooks_dir.join("notify-local-tts.sh");
    let settings_path = claude_dir.join("settings.json");
    let claude_md_path = claude_dir.join("CLAUDE.md");

    // 1. Create hooks directory if needed
    fs::create_dir_all(&hooks_dir)
        .map_err(|e| format!("Failed to create hooks directory: {}", e))?;

    // 2. Write the notification script
    fs::write(&script_path, NOTIFICATION_SCRIPT)
        .map_err(|e| format!("Failed to write notification script: {}", e))?;

    // 3. Make it executable (chmod +x)
    let mut perms = fs::metadata(&script_path)
        .map_err(|e| format!("Failed to get script metadata: {}", e))?
        .permissions();
    perms.set_mode(0o755);
    fs::set_permissions(&script_path, perms)
        .map_err(|e| format!("Failed to set script permissions: {}", e))?;

    // 4. Update settings.json with Stop hook
    let mut settings: serde_json::Value = if settings_path.exists() {
        let content = fs::read_to_string(&settings_path)
            .map_err(|e| format!("Failed to read settings.json: {}", e))?;
        serde_json::from_str(&content)
            .map_err(|e| format!("Failed to parse settings.json: {}", e))?
    } else {
        serde_json::json!({})
    };

    // Create the hook entry with expanded path
    let script_path_str = script_path.to_string_lossy().to_string();
    let hook_entry = serde_json::json!({
        "matcher": "",
        "hooks": [
            {
                "type": "command",
                "command": script_path_str,
                "async": true
            }
        ]
    });

    // Add to hooks.Stop array (create if doesn't exist)
    let hooks = settings
        .as_object_mut()
        .ok_or("Settings is not an object")?
        .entry("hooks")
        .or_insert(serde_json::json!({}));

    let stop_hooks = hooks
        .as_object_mut()
        .ok_or("Hooks is not an object")?
        .entry("Stop")
        .or_insert(serde_json::json!([]));

    // Check if already installed (avoid duplicates)
    let already_installed = stop_hooks
        .as_array()
        .map(|arr| arr.iter().any(hook_contains_notification_script))
        .unwrap_or(false);

    if !already_installed {
        if let Some(arr) = stop_hooks.as_array_mut() {
            arr.push(hook_entry);
        }
    }

    // Write settings back
    let settings_str = serde_json::to_string_pretty(&settings)
        .map_err(|e| format!("Failed to serialize settings: {}", e))?;
    fs::write(&settings_path, settings_str)
        .map_err(|e| format!("Failed to write settings.json: {}", e))?;

    // 5. Append Voice Notifications section to CLAUDE.md if not present
    let mut claude_md_content = if claude_md_path.exists() {
        fs::read_to_string(&claude_md_path)
            .map_err(|e| format!("Failed to read CLAUDE.md: {}", e))?
    } else {
        String::new()
    };

    if !claude_md_content.contains("## Voice Notifications") {
        claude_md_content.push_str(CLAUDE_MD_VOICE_SECTION);
        fs::write(&claude_md_path, claude_md_content)
            .map_err(|e| format!("Failed to write CLAUDE.md: {}", e))?;
    }

    Ok(())
}
