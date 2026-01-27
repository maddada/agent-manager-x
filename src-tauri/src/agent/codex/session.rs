//! Codex session building and parsing functionality.

use super::types::CodexJsonlLine;
use crate::agent::AgentProcess;
use crate::session::{AgentType, Session, SessionStatus};
use std::path::Path;

/// Get Codex sessions from conversation files.
pub fn get_codex_sessions(processes: &[AgentProcess]) -> Vec<Session> {
    let mut sessions = Vec::new();

    // Codex stores sessions in ~/.codex/sessions/
    let codex_dir = match dirs::home_dir() {
        Some(home) => home.join(".codex").join("sessions"),
        None => return sessions,
    };

    if !codex_dir.exists() {
        log::debug!("Codex sessions directory does not exist: {:?}", codex_dir);
        return sessions;
    }

    for process in processes {
        if let Some(cwd) = &process.cwd {
            // Find the most recent conversation for this working directory
            if let Some(session) = find_session_for_cwd(&codex_dir, cwd, process) {
                sessions.push(session);
            } else {
                // Create a basic session even without conversation data
                let project_name = cwd
                    .file_name()
                    .map(|n| n.to_string_lossy().to_string())
                    .unwrap_or_else(|| "Unknown".to_string());

                let status = if process.cpu_usage > 15.0 {
                    SessionStatus::Processing
                } else {
                    // No conversation data, treat as stale
                    SessionStatus::Stale
                };

                sessions.push(Session {
                    id: format!("codex-{}", process.pid),
                    agent_type: AgentType::Codex,
                    project_name,
                    project_path: cwd.to_string_lossy().to_string(),
                    git_branch: None,
                    github_url: None,
                    status,
                    last_message: None,
                    last_message_role: None,
                    last_activity_at: chrono::Utc::now().to_rfc3339(),
                    pid: process.pid,
                    cpu_usage: process.cpu_usage,
                    active_subagent_count: 0,
                });
            }
        }
    }

    sessions
}

/// Find a session file for a given working directory.
fn find_session_for_cwd(
    codex_dir: &Path,
    cwd: &Path,
    process: &AgentProcess,
) -> Option<Session> {
    let (file_path, modified) = find_latest_session_file(codex_dir)?;
    let content = std::fs::read_to_string(&file_path).ok()?;

    let (last_role, last_text) = extract_last_message_from_jsonl(&content);

    let project_name = cwd
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_else(|| "Unknown".to_string());

    let status = determine_status(process.cpu_usage, last_role.as_deref(), modified);

    let last_activity_at = modified
        .duration_since(std::time::UNIX_EPOCH)
        .ok()
        .and_then(|d| chrono::DateTime::from_timestamp(d.as_secs() as i64, 0))
        .map(|dt| dt.to_rfc3339())
        .unwrap_or_else(|| chrono::Utc::now().to_rfc3339());

    let session_id = file_path
        .file_stem()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_else(|| format!("codex-{}", process.pid));

    log::info!(
        "Codex session: id={}, project={}, status={:?}, last_role={:?}",
        session_id,
        project_name,
        status,
        last_role
    );

    Some(Session {
        id: session_id,
        agent_type: AgentType::Codex,
        project_name,
        project_path: cwd.to_string_lossy().to_string(),
        git_branch: None,
        github_url: None,
        status,
        last_message: last_text,
        last_message_role: last_role,
        last_activity_at,
        pid: process.pid,
        cpu_usage: process.cpu_usage,
        active_subagent_count: 0,
    })
}

/// Find the most recent JSONL session file in the sessions directory (recursive).
/// Codex stores sessions in nested directories: ~/.codex/sessions/YYYY/MM/DD/
fn find_latest_session_file(
    codex_dir: &Path,
) -> Option<(std::path::PathBuf, std::time::SystemTime)> {
    let mut latest_file: Option<(std::path::PathBuf, std::time::SystemTime)> = None;

    fn search_recursive(
        dir: &Path,
        latest: &mut Option<(std::path::PathBuf, std::time::SystemTime)>,
    ) {
        if let Ok(entries) = std::fs::read_dir(dir) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.is_dir() {
                    search_recursive(&path, latest);
                } else if path.extension().map(|e| e == "jsonl").unwrap_or(false) {
                    if let Ok(metadata) = path.metadata() {
                        if let Ok(modified) = metadata.modified() {
                            if latest.as_ref().map(|(_, t)| modified > *t).unwrap_or(true) {
                                *latest = Some((path, modified));
                            }
                        }
                    }
                }
            }
        }
    }

    search_recursive(codex_dir, &mut latest_file);
    latest_file
}

/// Extract the last message role and text from JSONL content.
fn extract_last_message_from_jsonl(content: &str) -> (Option<String>, Option<String>) {
    let mut last_role: Option<String> = None;
    let mut last_text: Option<String> = None;

    // Parse each line as JSON
    for line in content.lines() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }

        if let Ok(parsed) = serde_json::from_str::<CodexJsonlLine>(line) {
            // Look for response_item with message type
            if parsed.line_type == "response_item" {
                if let Some(payload) = &parsed.payload {
                    if payload.payload_type.as_deref() == Some("message") {
                        if let Some(role) = &payload.role {
                            // Map "developer" role to "user" for consistency
                            let normalized_role = if role == "developer" {
                                "user".to_string()
                            } else {
                                role.clone()
                            };

                            // Extract text from content
                            let text = payload.content.as_ref().and_then(|contents| {
                                contents.iter().find_map(|c| {
                                    if c.content_type == "output_text" || c.content_type == "input_text" {
                                        c.text.as_ref().map(|t| {
                                            if t.len() > 200 {
                                                format!("{}...", &t[..197])
                                            } else {
                                                t.clone()
                                            }
                                        })
                                    } else {
                                        None
                                    }
                                })
                            });

                            last_role = Some(normalized_role);
                            if text.is_some() {
                                last_text = text;
                            }
                        }
                    }
                }
            }
            // Also check event_msg for user messages
            else if parsed.line_type == "event_msg" {
                if let Some(payload) = &parsed.payload {
                    if payload.payload_type.as_deref() == Some("user_message") {
                        last_role = Some("user".to_string());
                        if let Some(msg) = &payload.message {
                            last_text = Some(if msg.len() > 200 {
                                format!("{}...", &msg[..197])
                            } else {
                                msg.clone()
                            });
                        }
                    }
                }
            }
        }
    }

    (last_role, last_text)
}

/// Determine session status based on CPU usage, last role, and time since last modification.
fn determine_status(cpu_usage: f32, last_role: Option<&str>, modified: std::time::SystemTime) -> SessionStatus {
    const IDLE_THRESHOLD_SECS: u64 = 5 * 60;
    const STALE_THRESHOLD_SECS: u64 = 10 * 60;

    let mut status = match (cpu_usage > 15.0, last_role) {
        (true, _) => SessionStatus::Processing,
        (_, Some("user")) => SessionStatus::Processing,
        _ => SessionStatus::Waiting,
    };

    // Time-based status upgrades: Waiting 5+ min -> Idle, 10+ min -> Stale
    if matches!(status, SessionStatus::Waiting) {
        if let Ok(elapsed) = modified.elapsed() {
            let age_secs = elapsed.as_secs();
            if age_secs >= STALE_THRESHOLD_SECS {
                status = SessionStatus::Stale;
            } else if age_secs >= IDLE_THRESHOLD_SECS {
                status = SessionStatus::Idle;
            }
        }
    }
    status
}
