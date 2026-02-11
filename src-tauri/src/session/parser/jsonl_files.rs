//! JSONL file discovery and session matching.

use log::{debug, trace};
use std::fs;
use std::path::PathBuf;
use std::time::{Duration, SystemTime};

use crate::agent::AgentProcess;
use crate::session::model::{AgentType, Session, SessionStatus};
use crate::session::status::status_sort_priority;

use super::session_parser::parse_session_file;
use super::subagent::{count_active_subagents, is_subagent_file};

/// Get JSONL files for a project, sorted by modification time (newest first)
/// Excludes subagent files (agent-*.jsonl) as they are counted separately
pub fn get_recently_active_jsonl_files(project_dir: &PathBuf) -> Vec<PathBuf> {
    let mut jsonl_files: Vec<_> = fs::read_dir(project_dir)
        .into_iter()
        .flatten()
        .flatten()
        .filter(|e| {
            let path = e.path();
            path.extension().map(|ext| ext == "jsonl").unwrap_or(false) && !is_subagent_file(&path)
        })
        .filter_map(|e| {
            let path = e.path();
            let modified = e.metadata().and_then(|m| m.modified()).ok()?;
            Some((path, modified))
        })
        .collect();

    // Sort by modification time (newest first)
    jsonl_files.sort_by(|a, b| b.1.cmp(&a.1));

    jsonl_files.into_iter().map(|(path, _)| path).collect()
}

/// Find a session for a specific process from available JSONL files
/// Checks all recent files and uses the most "active" status found
pub fn find_session_for_process(
    jsonl_files: &[PathBuf],
    project_dir: &PathBuf,
    project_path: &str,
    process: &AgentProcess,
    index: usize,
    agent_type: AgentType,
) -> Option<Session> {
    // Get the primary JSONL file at the given index
    let primary_jsonl = jsonl_files.get(index)?;

    // Parse the primary file first
    let mut session = parse_session_file(
        primary_jsonl,
        project_path,
        process.pid,
        process.cpu_usage,
        process.memory_bytes,
        agent_type.clone(),
    )?;

    // Count active subagents for this session
    session.active_subagent_count = count_active_subagents(project_dir, &session.id);

    // Check if any other recent files show more active status
    // This handles subagent scenarios where main session file stops updating
    let now = SystemTime::now();
    let active_threshold = Duration::from_secs(10); // Check files modified in last 10 seconds

    for jsonl_path in jsonl_files {
        if jsonl_path == primary_jsonl {
            continue;
        }

        // Only check recently modified files
        let is_recent = jsonl_path
            .metadata()
            .and_then(|m| m.modified())
            .ok()
            .and_then(|modified| now.duration_since(modified).ok())
            .map(|d| d < active_threshold)
            .unwrap_or(false);

        if !is_recent {
            continue;
        }

        // Parse this file and check its status
        if let Some(other_session) = parse_session_file(
            jsonl_path,
            project_path,
            process.pid,
            process.cpu_usage,
            process.memory_bytes,
            agent_type.clone(),
        ) {
            // CRITICAL: Only consider files from the SAME session
            // Without this check, one session's active status can contaminate another
            if other_session.id != session.id {
                trace!(
                    "Skipping status from different session: {} (current) vs {} (other)",
                    session.id,
                    other_session.id
                );
                continue;
            }

            // If this file shows a more active status, use it
            let current_priority = status_sort_priority(&session.status);
            let other_priority = status_sort_priority(&other_session.status);

            if other_priority < current_priority {
                debug!(
                    "Found more active status in {:?}: {:?} -> {:?}",
                    jsonl_path, session.status, other_session.status
                );
                session.status = other_session.status;
            }
        }
    }

    // Additional check: if CPU usage is high AND message is recent, the process is likely working
    // Only override if CPU > 15% (higher threshold to avoid false positives from background tasks)
    // AND the last message was recent (not stale) - idle processes with old messages shouldn't be marked active
    const CPU_OVERRIDE_THRESHOLD: f32 = 15.0;
    const STALENESS_THRESHOLD_SECS: i64 = 30;

    let message_is_stale_for_cpu = chrono::DateTime::parse_from_rfc3339(&session.last_activity_at)
        .ok()
        .map(|dt| {
            let age_secs = chrono::Utc::now()
                .signed_duration_since(dt.with_timezone(&chrono::Utc))
                .num_seconds();
            age_secs > STALENESS_THRESHOLD_SECS
        })
        .unwrap_or(true);

    if matches!(session.status, SessionStatus::Waiting)
        && process.cpu_usage > CPU_OVERRIDE_THRESHOLD
        && !message_is_stale_for_cpu
    {
        debug!(
            "Process has high CPU ({:.1}%) and recent message, overriding Waiting -> Processing",
            process.cpu_usage
        );
        session.status = SessionStatus::Processing;
    }

    Some(session)
}
