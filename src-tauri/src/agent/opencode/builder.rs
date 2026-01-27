//! Session builder utilities for OpenCode
//!
//! This module provides helper functions for building Session objects
//! from OpenCode data, including status determination and formatting.

use super::message::get_last_message;
use super::types::OpenCodeSession;
use crate::agent::AgentProcess;
use crate::session::{AgentType, Session, SessionStatus};
use std::path::PathBuf;

/// Time threshold constants for status determination
const IDLE_THRESHOLD_SECS: i64 = 5 * 60;
const STALE_THRESHOLD_SECS: i64 = 10 * 60;

/// Determine session status based on CPU usage, last message role, and time
pub fn determine_status(
    process: &AgentProcess,
    last_role: Option<&str>,
    updated_ms: u64,
) -> SessionStatus {
    // Determine base status
    let mut status = if process.cpu_usage > 15.0 {
        SessionStatus::Processing
    } else if last_role == Some("assistant") {
        SessionStatus::Waiting
    } else if last_role == Some("user") {
        SessionStatus::Processing
    } else {
        SessionStatus::Waiting
    };

    // Time-based status upgrades: Waiting 5+ min -> Idle, 10+ min -> Stale
    if matches!(status, SessionStatus::Waiting) {
        let updated_secs = (updated_ms / 1000) as i64;
        let now_secs = chrono::Utc::now().timestamp();
        let age_secs = now_secs - updated_secs;

        if age_secs >= STALE_THRESHOLD_SECS {
            status = SessionStatus::Stale;
        } else if age_secs >= IDLE_THRESHOLD_SECS {
            status = SessionStatus::Idle;
        }
    }

    status
}

/// Convert millisecond timestamp to ISO string
pub fn timestamp_to_iso(updated_ms: u64) -> String {
    let updated_secs = updated_ms / 1000;
    chrono::DateTime::from_timestamp(updated_secs as i64, 0)
        .map(|dt| dt.format("%Y-%m-%dT%H:%M:%S%.3fZ").to_string())
        .unwrap_or_else(|| "Unknown".to_string())
}

/// Extract project name from a path
pub fn extract_project_name(path: &str) -> String {
    path.split('/')
        .filter(|s| !s.is_empty())
        .last()
        .unwrap_or("Unknown")
        .to_string()
}

/// Build a Session object from OpenCode session data and process info
pub fn build_session(
    storage_path: &PathBuf,
    session: OpenCodeSession,
    process: &AgentProcess,
    project_path: String,
) -> Session {
    // Get the last message for status detection and display
    let (last_role, last_message_text, _) = get_last_message(storage_path, &session.id);

    let status = determine_status(process, last_role.as_deref(), session.time.updated);
    let last_activity_at = timestamp_to_iso(session.time.updated);
    let project_name = extract_project_name(&project_path);

    log::info!(
        "OpenCode session: id={}, project={}, status={:?}, last_role={:?}, cpu={:.1}%",
        session.id,
        project_name,
        status,
        last_role,
        process.cpu_usage
    );

    // Use message text if available, fall back to session title
    let display_message =
        last_message_text.or_else(|| Some(session.title.clone()).filter(|t| !t.is_empty()));

    Session {
        id: session.id,
        agent_type: AgentType::OpenCode,
        project_name,
        project_path,
        git_branch: None,
        github_url: None,
        status,
        last_message: display_message,
        last_message_role: last_role,
        last_activity_at,
        pid: process.pid,
        cpu_usage: process.cpu_usage,
        active_subagent_count: 0,
    }
}
