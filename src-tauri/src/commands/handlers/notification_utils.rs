//! Utility functions for notification system

/// Check if a hook entry contains the notification script
pub fn hook_contains_notification_script(entry: &serde_json::Value) -> bool {
    if let Some(inner_hooks) = entry.get("hooks") {
        if let Some(inner_arr) = inner_hooks.as_array() {
            for hook in inner_arr {
                if let Some(cmd) = hook.get("command") {
                    if let Some(cmd_str) = cmd.as_str() {
                        if cmd_str.contains("notify-local-tts.sh") {
                            return true;
                        }
                    }
                }
            }
        }
    }
    false
}
