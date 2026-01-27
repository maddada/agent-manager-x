//! Debug-related command handlers

use std::fs;

/// Write debug log to a file (for debugging purposes)
#[tauri::command]
pub fn write_debug_log(content: String) -> Result<String, String> {
    let path = "/tmp/agent-manager-x-debug.log";
    fs::write(path, content).map_err(|e| format!("Failed to write debug log: {}", e))?;
    Ok(path.to_string())
}
