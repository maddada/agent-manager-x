//! Subagent detection and counting utilities.

use log::trace;
use std::fs::{self, File};
use std::io::{BufRead, BufReader};
use std::path::PathBuf;
use std::time::{Duration, SystemTime};

use crate::session::model::JsonlMessage;

/// Check if a JSONL file is a subagent file (named agent-*.jsonl)
pub fn is_subagent_file(path: &PathBuf) -> bool {
    path.file_name()
        .and_then(|n| n.to_str())
        .map(|name| name.starts_with("agent-") && name.ends_with(".jsonl"))
        .unwrap_or(false)
}

/// Extract sessionId from a subagent JSONL file by reading the first few lines
pub fn get_subagent_session_id(path: &PathBuf) -> Option<String> {
    let file = File::open(path).ok()?;
    let reader = BufReader::new(file);

    // Check first 5 lines for sessionId
    for line in reader.lines().take(5).flatten() {
        if let Ok(msg) = serde_json::from_str::<JsonlMessage>(&line) {
            if let Some(session_id) = msg.session_id {
                return Some(session_id);
            }
        }
    }
    None
}

/// Count active subagents for a given parent session
pub fn count_active_subagents(project_dir: &PathBuf, parent_session_id: &str) -> usize {
    let active_threshold = Duration::from_secs(30);
    let now = SystemTime::now();

    let count = fs::read_dir(project_dir)
        .into_iter()
        .flatten()
        .flatten()
        .filter(|e| is_subagent_file(&e.path()))
        .filter(|e| {
            // Check if file was recently modified
            e.metadata()
                .and_then(|m| m.modified())
                .ok()
                .and_then(|modified| now.duration_since(modified).ok())
                .map(|d| d < active_threshold)
                .unwrap_or(false)
        })
        .filter(|e| {
            // Check if sessionId matches parent
            get_subagent_session_id(&e.path())
                .map(|id| id == parent_session_id)
                .unwrap_or(false)
        })
        .count();

    trace!(
        "Found {} active subagents for session {}",
        count,
        parent_session_id
    );
    count
}
