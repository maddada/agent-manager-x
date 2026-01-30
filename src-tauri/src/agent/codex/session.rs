//! Codex session building and parsing functionality.

use crate::agent::AgentProcess;
use crate::session::{AgentType, Session, SessionStatus};
use serde_json::Value;
use std::collections::{HashMap, VecDeque};
use std::fs::File;
use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::time::SystemTime;

#[derive(Debug, Clone)]
struct CodexSessionFile {
    path: PathBuf,
    modified: SystemTime,
    cwd: Option<String>,
    session_id: Option<String>,
    last_message: Option<String>,
    last_role: Option<String>,
    last_activity_at: Option<String>,
}

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

    let session_files = collect_codex_session_files(&codex_dir);

    // Build lookup: cwd -> session files (newest first)
    let mut files_by_cwd: HashMap<String, VecDeque<usize>> = HashMap::new();
    for (index, file) in session_files.iter().enumerate() {
        if let Some(cwd) = &file.cwd {
            files_by_cwd.entry(cwd.clone()).or_default().push_back(index);
        }
    }
    for queue in files_by_cwd.values_mut() {
        let mut indices: Vec<_> = queue.drain(..).collect();
        indices.sort_by(|a, b| session_files[*b].modified.cmp(&session_files[*a].modified));
        *queue = VecDeque::from(indices);
    }

    let mut all_indices: Vec<_> = (0..session_files.len()).collect();
    all_indices.sort_by(|a, b| session_files[*b].modified.cmp(&session_files[*a].modified));
    let mut fallback_queue: VecDeque<usize> = VecDeque::from(all_indices);
    let mut used: Vec<bool> = vec![false; session_files.len()];

    for process in processes {
        let mut assigned_index: Option<usize> = None;
        if let Some(cwd) = &process.cwd {
            let cwd_str = cwd.to_string_lossy().to_string();
            if let Some(queue) = files_by_cwd.get_mut(&cwd_str) {
                while let Some(idx) = queue.pop_front() {
                    if !used[idx] {
                        assigned_index = Some(idx);
                        break;
                    }
                }
            }
        }

        if assigned_index.is_none() {
            while let Some(idx) = fallback_queue.pop_front() {
                if !used[idx] {
                    assigned_index = Some(idx);
                    break;
                }
            }
        }

        if let Some(idx) = assigned_index {
            used[idx] = true;
            if let Some(session) = build_session_from_file(&session_files[idx], process) {
                sessions.push(session);
                continue;
            }
        }

        // Fallback: create a basic session even without conversation data
        let (project_name, project_path) = if let Some(cwd) = &process.cwd {
            (
                cwd.file_name()
                    .map(|n| n.to_string_lossy().to_string())
                    .unwrap_or_else(|| "Unknown".to_string()),
                cwd.to_string_lossy().to_string(),
            )
        } else {
            ("Unknown".to_string(), "/".to_string())
        };

        let status = if process.cpu_usage > 15.0 {
            SessionStatus::Processing
        } else {
            // No conversation data, treat as stale
            SessionStatus::Stale
        };

        let is_background = is_background_session(&project_path, &None);
        let fallback_session = Session {
            id: format!("codex-{}", process.pid),
            agent_type: AgentType::Codex,
            project_name,
            project_path,
            git_branch: None,
            github_url: None,
            status,
            last_message: None,
            last_message_role: None,
            last_activity_at: chrono::Utc::now().to_rfc3339(),
            pid: process.pid,
            cpu_usage: process.cpu_usage,
            memory_bytes: process.memory_bytes,
            active_subagent_count: 0,
            is_background,
        };
        sessions.push(fallback_session);
    }

    sessions
}

fn collect_codex_session_files(codex_dir: &Path) -> Vec<CodexSessionFile> {
    let mut files = Vec::new();

    fn search_recursive(dir: &Path, files: &mut Vec<CodexSessionFile>) {
        if let Ok(entries) = std::fs::read_dir(dir) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.is_dir() {
                    search_recursive(&path, files);
                } else if path.extension().map(|e| e == "jsonl").unwrap_or(false) {
                    if let Ok(metadata) = path.metadata() {
                        if let Ok(modified) = metadata.modified() {
                            if let Some(parsed) = parse_codex_session_file(&path, modified) {
                                files.push(parsed);
                            }
                        }
                    }
                }
            }
        }
    }

    search_recursive(codex_dir, &mut files);
    files
}

fn build_session_from_file(file: &CodexSessionFile, process: &AgentProcess) -> Option<Session> {
    let project_path = file
        .cwd
        .clone()
        .or_else(|| process.cwd.as_ref().map(|p| p.to_string_lossy().to_string()))
        .unwrap_or_else(|| "/".to_string());
    let project_name = Path::new(&project_path)
        .file_name()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_else(|| "Unknown".to_string());

    let status = determine_status(process.cpu_usage, file.last_role.as_deref(), file.modified);
    let last_activity_at = file
        .last_activity_at
        .clone()
        .unwrap_or_else(|| system_time_to_rfc3339(file.modified));

    let session_id = file
        .path
        .file_stem()
        .map(|s| s.to_string_lossy().to_string())
        .or_else(|| file.session_id.clone())
        .unwrap_or_else(|| format!("codex-{}", process.pid));

    let is_background = is_background_session(&project_path, &file.last_message);

    if project_path == "/" || project_name == "Unknown" {
        log::warn!(
            "Codex session resolved to Unknown project: session_id={}, file={:?}, file_cwd={:?}, process_cwd={:?}",
            session_id,
            file.path,
            file.cwd,
            process.cwd
        );
    }

    log::info!(
        "Codex session: id={}, project={}, status={:?}, last_role={:?}",
        session_id,
        project_name,
        status,
        file.last_role
    );

    Some(Session {
        id: session_id,
        agent_type: AgentType::Codex,
        project_name,
        project_path,
        git_branch: None,
        github_url: None,
        status,
        last_message: file.last_message.clone(),
        last_message_role: file.last_role.clone(),
        last_activity_at,
        pid: process.pid,
        cpu_usage: process.cpu_usage,
        memory_bytes: process.memory_bytes,
        active_subagent_count: 0,
        is_background,
    })
}

fn is_background_session(project_path: &str, last_message: &Option<String>) -> bool {
    if project_path != "/" {
        return false;
    }
    last_message
        .as_ref()
        .map(|msg| msg.trim().is_empty())
        .unwrap_or(true)
}

fn parse_codex_session_file(path: &Path, modified: SystemTime) -> Option<CodexSessionFile> {
    let file = File::open(path).ok()?;
    let reader = BufReader::new(file);

    let mut session_id: Option<String> = None;
    let mut cwd_meta: Option<String> = None;
    let mut cwd_turn: Option<String> = None;
    let mut cwd_env: Option<String> = None;
    let mut last_message: Option<String> = None;
    let mut last_role: Option<String> = None;
    let mut last_activity_at: Option<String> = None;

    for line in reader.lines().flatten() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }

        let Ok(parsed) = serde_json::from_str::<Value>(line) else {
            continue;
        };

        let line_type = parsed.get("type").and_then(|t| t.as_str()).unwrap_or("");

        match line_type {
            "session_meta" => {
                if let Some(payload) = parsed.get("payload") {
                    if session_id.is_none() {
                        session_id = payload
                            .get("id")
                            .and_then(|v| v.as_str())
                            .map(|s| s.to_string());
                    }
                    if cwd_meta.is_none() {
                        cwd_meta = payload
                            .get("cwd")
                            .and_then(|v| v.as_str())
                            .map(|s| s.to_string());
                    }
                }
            }
            "turn_context" => {
                if let Some(payload) = parsed.get("payload") {
                    if let Some(cwd) = payload.get("cwd").and_then(|v| v.as_str()) {
                        if !cwd.is_empty() {
                            cwd_turn = Some(cwd.to_string());
                        }
                    }
                }
            }
            "response_item" => {
                if let Some(payload) = parsed.get("payload") {
                    if payload.get("type").and_then(|v| v.as_str()) == Some("message") {
                        let role = payload.get("role").and_then(|v| v.as_str());
                        if let Some(text) = extract_text_from_payload(payload) {
                            if let Some(cwd) = extract_cwd_from_environment_context(&text) {
                                cwd_env = Some(cwd);
                            }
                            if let Some(role) = role {
                                if role == "assistant" || role == "user" {
                                    if let Some(cleaned) = normalize_codex_message_text(&text) {
                                        last_message = Some(cleaned);
                                        last_role = Some(role.to_string());
                                        last_activity_at = parsed
                                            .get("timestamp")
                                            .and_then(|v| v.as_str())
                                            .map(|s| s.to_string());
                                    }
                                }
                            }
                        }
                    }
                }
            }
            "event_msg" => {
                if let Some(payload) = parsed.get("payload") {
                    if payload.get("type").and_then(|v| v.as_str()) == Some("user_message") {
                        if let Some(message) = payload.get("message").and_then(|v| v.as_str()) {
                            if let Some(cwd) = extract_cwd_from_environment_context(message) {
                                cwd_env = Some(cwd);
                            }
                            if let Some(cleaned) = normalize_codex_message_text(message) {
                                last_message = Some(cleaned);
                                last_role = Some("user".to_string());
                                last_activity_at = parsed
                                    .get("timestamp")
                                    .and_then(|v| v.as_str())
                                    .map(|s| s.to_string());
                            }
                        }
                    }
                }
            }
            _ => {}
        }
    }

    let cwd = select_best_cwd(cwd_turn.clone(), cwd_env.clone(), cwd_meta.clone());
    if matches!(cwd.as_deref(), None | Some("/")) {
        log::warn!(
            "Codex session file has no usable cwd: file={:?}, session_id={:?}, cwd_turn={:?}, cwd_env={:?}, cwd_meta={:?}",
            path,
            session_id,
            cwd_turn,
            cwd_env,
            cwd_meta
        );
    }

    Some(CodexSessionFile {
        path: path.to_path_buf(),
        modified,
        cwd,
        session_id,
        last_message,
        last_role,
        last_activity_at,
    })
}

fn extract_text_from_payload(payload: &Value) -> Option<String> {
    let content = payload.get("content")?.as_array()?;
    for item in content {
        let content_type = item.get("type").and_then(|v| v.as_str()).unwrap_or("");
        if content_type == "output_text" || content_type == "input_text" {
            if let Some(text) = item.get("text").and_then(|v| v.as_str()) {
                return Some(text.to_string());
            }
        }
    }
    None
}

fn normalize_codex_message_text(text: &str) -> Option<String> {
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return None;
    }
    if trimmed.starts_with("<environment_context>")
        || trimmed.starts_with("<permissions instructions>")
        || trimmed.starts_with("# AGENTS.md instructions")
    {
        return None;
    }

    Some(truncate_message(trimmed, 200))
}

fn truncate_message(text: &str, max_len: usize) -> String {
    let mut chars = text.chars();
    let mut buf = String::new();
    for _ in 0..max_len {
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

fn extract_cwd_from_environment_context(text: &str) -> Option<String> {
    let trimmed = text.trim();
    if !trimmed.contains("<cwd>") {
        return None;
    }
    let start = trimmed.find("<cwd>")? + "<cwd>".len();
    let rest = &trimmed[start..];
    let end = rest.find("</cwd>")?;
    let cwd = rest[..end].trim();
    if cwd.is_empty() {
        None
    } else {
        Some(cwd.to_string())
    }
}

fn select_best_cwd(
    cwd_turn: Option<String>,
    cwd_env: Option<String>,
    cwd_meta: Option<String>,
) -> Option<String> {
    for candidate in [&cwd_turn, &cwd_env, &cwd_meta] {
        if let Some(value) = candidate {
            let trimmed = value.trim();
            if !trimmed.is_empty() && trimmed != "/" {
                return Some(trimmed.to_string());
            }
        }
    }

    for candidate in [cwd_turn, cwd_env, cwd_meta] {
        if let Some(value) = candidate {
            let trimmed = value.trim();
            if !trimmed.is_empty() {
                return Some(trimmed.to_string());
            }
        }
    }
    None
}

fn system_time_to_rfc3339(time: SystemTime) -> String {
    time.duration_since(std::time::UNIX_EPOCH)
        .ok()
        .and_then(|d| chrono::DateTime::from_timestamp(d.as_secs() as i64, 0))
        .map(|dt| dt.to_rfc3339())
        .unwrap_or_else(|| chrono::Utc::now().to_rfc3339())
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
