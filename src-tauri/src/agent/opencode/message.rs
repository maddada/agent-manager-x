//! OpenCode message handling

use super::types::{OpenCodeMessage, OpenCodePart};
use std::path::PathBuf;

/// Get the last message role, time, and text for a session
pub fn get_last_message(
    storage_path: &PathBuf,
    session_id: &str,
) -> (Option<String>, Option<String>, u64) {
    let message_dir = storage_path.join("message").join(session_id);

    if !message_dir.exists() {
        log::debug!("Message dir does not exist: {:?}", message_dir);
        return (None, None, 0);
    }

    // Collect all messages sorted by created time (descending)
    let mut messages: Vec<(String, String, u64)> = Vec::new(); // (role, message_id, created)

    if let Ok(entries) = std::fs::read_dir(&message_dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.extension().map(|e| e == "json").unwrap_or(false) {
                if let Ok(content) = std::fs::read_to_string(&path) {
                    if let Ok(msg) = serde_json::from_str::<OpenCodeMessage>(&content) {
                        messages.push((msg.role, msg.id, msg.time.created));
                    }
                }
            }
        }
    }

    // Sort by created time descending (newest first)
    messages.sort_by(|a, b| b.2.cmp(&a.2));

    let message_count = messages.len();

    // Find the first message with displayable text (skip system prompts)
    for (role, message_id, time) in messages {
        if let Some(text) = get_message_text(storage_path, &message_id) {
            let preview = truncate_chars(&text, 50);
            log::debug!(
                "Session {} has {} messages, showing: id={}, role={}, created={}, text={:?}",
                session_id,
                message_count,
                message_id,
                role,
                time,
                preview
            );
            return (Some(role), Some(text), time);
        }
    }

    log::debug!(
        "Session {} has {} messages but no displayable text",
        session_id,
        message_count
    );
    (None, None, 0)
}

/// Get the text content from a message's parts
fn get_message_text(storage_path: &PathBuf, message_id: &str) -> Option<String> {
    let part_dir = storage_path.join("part").join(message_id);

    if !part_dir.exists() {
        return None;
    }

    let mut text_content: Option<String> = None;
    let mut reasoning_content: Option<String> = None;

    // Find the "text" type part (preferred), or "reasoning" as fallback
    if let Ok(entries) = std::fs::read_dir(&part_dir) {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.extension().map(|e| e == "json").unwrap_or(false) {
                if let Ok(content) = std::fs::read_to_string(&path) {
                    if let Ok(part) = serde_json::from_str::<OpenCodePart>(&content) {
                        if part.part_type == "text" {
                            if let Some(text) = part.text {
                                text_content = Some(text);
                            }
                        } else if part.part_type == "reasoning" && reasoning_content.is_none() {
                            if let Some(text) = part.text {
                                reasoning_content = Some(text);
                            }
                        }
                    }
                }
            }
        }
    }

    // Prefer text content, fall back to reasoning
    let content = text_content.or(reasoning_content)?;

    // Skip system prompts (XML-formatted instructions)
    let trimmed = content.trim();
    if trimmed.starts_with('<') && (trimmed.contains("ultrawork") || trimmed.contains("mode>")) {
        return None;
    }

    // Truncate if too long
    Some(truncate_chars(&content, 200))
}

fn truncate_chars(text: &str, max_chars: usize) -> String {
    let mut chars = text.chars();
    let mut buf = String::new();
    for _ in 0..max_chars {
        if let Some(c) = chars.next() {
            buf.push(c);
        } else {
            return text.to_string();
        }
    }
    if chars.next().is_some() {
        buf.push_str("...");
    }
    buf
}
