//! Message extraction from JSONL lines.

use log::debug;
use std::collections::VecDeque;
use std::fs::File;
use std::io::{BufRead, BufReader};
use std::path::PathBuf;

use crate::session::model::JsonlMessage;
use crate::session::status::{
    has_tool_result, has_tool_use, is_interrupted_request, is_local_slash_command,
};

use super::utils::get_content_preview;

/// Extracted message data from JSONL file
pub struct ExtractedMessageData {
    pub session_id: Option<String>,
    pub git_branch: Option<String>,
    pub last_timestamp: Option<String>,
    pub last_message: Option<String>,
    pub last_user_message: Option<String>,
    pub last_role: Option<String>,
    pub last_msg_type: Option<String>,
    pub last_has_tool_use: bool,
    pub last_has_tool_result: bool,
    pub last_is_local_command: bool,
    pub last_is_interrupted: bool,
}

/// Extract message data from a JSONL file
pub fn extract_message_data(jsonl_path: &PathBuf) -> Option<ExtractedMessageData> {
    let file = File::open(jsonl_path).ok()?;
    let reader = BufReader::new(file);

    let mut session_id = None;
    let mut git_branch = None;
    let mut last_timestamp = None;
    let mut last_message = None;
    let mut last_user_message = None;
    let mut last_role = None;
    let mut last_msg_type = None;
    let mut last_has_tool_use = false;
    let mut last_has_tool_result = false;
    let mut last_is_local_command = false;
    let mut last_is_interrupted = false;
    let mut found_status_info = false;

    // Use a ring buffer to keep only the last 100 lines (memory efficient for large files)
    const MAX_LINES: usize = 100;
    let mut last_lines: VecDeque<String> = VecDeque::with_capacity(MAX_LINES);
    for line in reader.lines().flatten() {
        if last_lines.len() >= MAX_LINES {
            last_lines.pop_front();
        }
        last_lines.push_back(line);
    }

    log::trace!("Checking last {} lines from file", last_lines.len());

    for line in last_lines.iter().rev() {
        if let Ok(msg) = serde_json::from_str::<JsonlMessage>(line) {
            if session_id.is_none() {
                session_id = msg.session_id;
            }
            if git_branch.is_none() {
                git_branch = msg.git_branch;
            }
            if last_timestamp.is_none() {
                last_timestamp = msg.timestamp;
            }

            // For status detection, we need to find the most recent message that has CONTENT
            if !found_status_info {
                if let Some(content) = &msg.message {
                    if let Some(c) = &content.content {
                        let has_content = match c {
                            serde_json::Value::String(s) => !s.is_empty(),
                            serde_json::Value::Array(arr) => !arr.is_empty(),
                            _ => false,
                        };

                        if has_content {
                            last_msg_type = msg.msg_type.clone();
                            last_role = content.role.clone();
                            last_has_tool_use = has_tool_use(c);
                            last_has_tool_result = has_tool_result(c);
                            last_is_local_command = is_local_slash_command(c);
                            last_is_interrupted = is_interrupted_request(c);
                            found_status_info = true;

                            // Enhanced logging with content preview
                            let content_preview = get_content_preview(c);
                            debug!(
                                "Found status info: type={:?}, role={:?}, has_tool_use={}, has_tool_result={}, is_local_cmd={}, is_interrupted={}, content={}",
                                last_msg_type, last_role, last_has_tool_use, last_has_tool_result, last_is_local_command, last_is_interrupted, content_preview
                            );
                        }
                    }
                }
            }

            if session_id.is_some() && found_status_info {
                break;
            }
        }
    }

    // Now find the last meaningful text message and last user message
    for line in last_lines.iter().rev() {
        if let Ok(msg) = serde_json::from_str::<JsonlMessage>(line) {
            if let Some(content) = &msg.message {
                if let Some(c) = &content.content {
                    let text = match c {
                        serde_json::Value::String(s) if !s.is_empty() => Some(s.clone()),
                        serde_json::Value::Array(arr) => arr.iter().find_map(|v| {
                            v.get("text")
                                .and_then(|t| t.as_str())
                                .filter(|s| !s.is_empty())
                                .map(String::from)
                        }),
                        _ => None,
                    };

                    if let Some(text) = text {
                        if last_message.is_none() {
                            last_message = Some(text.clone());
                        }
                        if content.role.as_deref() == Some("user") && last_user_message.is_none() {
                            last_user_message = Some(text.clone());
                        }
                        if last_message.is_some() && last_user_message.is_some() {
                            break;
                        }
                    }
                }
            }
        }
    }

    Some(ExtractedMessageData {
        session_id,
        git_branch,
        last_timestamp,
        last_message,
        last_user_message,
        last_role,
        last_msg_type,
        last_has_tool_use,
        last_has_tool_result,
        last_is_local_command,
        last_is_interrupted,
    })
}
