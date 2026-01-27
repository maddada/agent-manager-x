//! Session file parsing - converts JSONL files into Session structs.

use log::debug;
use std::path::PathBuf;
use std::time::SystemTime;

use crate::session::model::{AgentType, Session, SessionStatus};
use crate::session::status::determine_status;

use super::message_extraction::extract_message_data;
use super::utils::get_github_url;

/// Parse a JSONL session file and create a Session struct
pub fn parse_session_file(
    jsonl_path: &PathBuf,
    project_path: &str,
    pid: u32,
    cpu_usage: f32,
    agent_type: AgentType,
) -> Option<Session> {
    debug!("Parsing JSONL file: {:?}", jsonl_path);

    // Check if the file was modified very recently (indicates active processing)
    let file_age_secs = jsonl_path
        .metadata()
        .and_then(|m| m.modified())
        .ok()
        .and_then(|modified| SystemTime::now().duration_since(modified).ok())
        .map(|d| d.as_secs_f32());

    let file_recently_modified = file_age_secs.map(|age| age < 3.0).unwrap_or(false);

    debug!(
        "File age: {:.1}s, recently_modified: {}",
        file_age_secs.unwrap_or(-1.0),
        file_recently_modified
    );

    // Extract message data from the file
    let data = extract_message_data(jsonl_path)?;
    let session_id = data.session_id?;

    // Calculate message staleness from timestamp
    // Messages older than 30 seconds are considered stale
    const STALENESS_THRESHOLD_SECS: i64 = 30;
    let message_is_stale = data.last_timestamp
        .as_ref()
        .and_then(|ts| chrono::DateTime::parse_from_rfc3339(ts).ok())
        .map(|dt| {
            let age_secs = chrono::Utc::now()
                .signed_duration_since(dt.with_timezone(&chrono::Utc))
                .num_seconds();
            age_secs > STALENESS_THRESHOLD_SECS
        })
        .unwrap_or(true); // Treat unknown timestamps as stale

    // Determine status based on message type, content, and file activity
    let mut status = determine_status(
        data.last_msg_type.as_deref(),
        data.last_has_tool_use,
        data.last_has_tool_result,
        data.last_is_local_command,
        data.last_is_interrupted,
        file_recently_modified,
        message_is_stale,
    );

    // Time-based status upgrades for inactive sessions
    // Waiting for 5+ minutes -> Idle, 10+ minutes -> Stale
    const IDLE_THRESHOLD_SECS: i64 = 5 * 60;   // 5 minutes
    const STALE_THRESHOLD_SECS: i64 = 10 * 60; // 10 minutes

    if matches!(status, SessionStatus::Waiting | SessionStatus::Idle) {
        if let Some(age_secs) = data.last_timestamp
            .as_ref()
            .and_then(|ts| chrono::DateTime::parse_from_rfc3339(ts).ok())
            .map(|dt| {
                chrono::Utc::now()
                    .signed_duration_since(dt.with_timezone(&chrono::Utc))
                    .num_seconds()
            })
        {
            if age_secs >= STALE_THRESHOLD_SECS {
                status = SessionStatus::Stale;
            } else if age_secs >= IDLE_THRESHOLD_SECS {
                status = SessionStatus::Idle;
            }
        }
    }

    debug!(
        "Status determination: type={:?}, tool_use={}, tool_result={}, local_cmd={}, interrupted={}, recent={} -> {:?}",
        data.last_msg_type, data.last_has_tool_use, data.last_has_tool_result, data.last_is_local_command, data.last_is_interrupted, file_recently_modified, status
    );

    // Extract project name from path
    let project_name = project_path
        .split('/')
        .filter(|s| !s.is_empty())
        .last()
        .unwrap_or("Unknown")
        .to_string();

    // Truncate message for preview (respecting UTF-8 char boundaries)
    // Use a high limit to allow full messages in tooltips while protecting against edge cases
    let last_message = data.last_message.map(|m| {
        if m.chars().count() > 5000 {
            format!("{}...", m.chars().take(5000).collect::<String>())
        } else {
            m
        }
    });

    // Get GitHub URL from git remote
    let github_url = get_github_url(project_path);

    Some(Session {
        id: session_id,
        agent_type,
        project_name,
        project_path: project_path.to_string(),
        git_branch: data.git_branch,
        github_url,
        status,
        last_message,
        last_message_role: data.last_role,
        last_activity_at: data.last_timestamp.unwrap_or_else(|| "Unknown".to_string()),
        pid,
        cpu_usage,
        active_subagent_count: 0, // Set by find_session_for_process
    })
}
