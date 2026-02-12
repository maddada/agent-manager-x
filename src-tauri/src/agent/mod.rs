pub mod claude;
pub mod codex;
pub mod opencode;

use crate::session::{AgentType, Session, SessionsResponse};

/// Common process info shared across agent types
#[derive(Debug, Clone)]
pub struct AgentProcess {
    pub pid: u32,
    pub cpu_usage: f32,
    pub memory_bytes: u64,
    pub cwd: Option<std::path::PathBuf>,
    pub data_home: Option<std::path::PathBuf>,
    pub active_session_file: Option<std::path::PathBuf>,
}

/// Trait for detecting and parsing agent sessions
pub trait AgentDetector: Send + Sync {
    /// Human-readable name of the agent
    fn name(&self) -> &'static str;

    /// The agent type for tagging sessions
    fn agent_type(&self) -> AgentType;

    /// Find running processes for this agent
    fn find_processes(&self) -> Vec<AgentProcess>;

    /// Parse sessions from data files, matched to running processes
    fn find_sessions(&self, processes: &[AgentProcess]) -> Vec<Session>;
}

/// Get all sessions from all registered agent detectors
pub fn get_all_sessions() -> SessionsResponse {
    use crate::session::status_sort_priority;

    let detectors: Vec<Box<dyn AgentDetector>> = vec![
        Box::new(claude::ClaudeDetector),
        Box::new(codex::CodexDetector),
        Box::new(opencode::OpenCodeDetector),
    ];

    let mut all_sessions = Vec::new();

    for detector in &detectors {
        let processes = detector.find_processes();
        let sessions = detector.find_sessions(&processes);
        log::info!(
            "{}: found {} processes, {} sessions",
            detector.name(),
            processes.len(),
            sessions.len()
        );
        all_sessions.extend(sessions);
    }

    let mut foreground_sessions = Vec::new();
    let mut background_sessions = Vec::new();
    for session in all_sessions {
        if session.is_background {
            background_sessions.push(session);
        } else {
            foreground_sessions.push(session);
        }
    }

    // Sort foreground by status priority first, then by most recent activity
    foreground_sessions.sort_by(|a, b| {
        let priority_a = status_sort_priority(&a.status);
        let priority_b = status_sort_priority(&b.status);

        if priority_a != priority_b {
            priority_a.cmp(&priority_b)
        } else {
            b.last_activity_at.cmp(&a.last_activity_at)
        }
    });

    // Sort background by agent type then by most recent activity
    let agent_sort_key = |agent_type: &AgentType| match agent_type {
        AgentType::Claude => 0,
        AgentType::Codex => 1,
        AgentType::OpenCode => 2,
    };

    background_sessions.sort_by(|a, b| {
        let key_a = agent_sort_key(&a.agent_type);
        let key_b = agent_sort_key(&b.agent_type);
        if key_a != key_b {
            key_a.cmp(&key_b)
        } else {
            b.last_activity_at.cmp(&a.last_activity_at)
        }
    });

    let waiting_count = foreground_sessions
        .iter()
        .filter(|s| matches!(s.status, crate::session::SessionStatus::Waiting))
        .count();
    let total_count = foreground_sessions.len();

    SessionsResponse {
        sessions: foreground_sessions,
        background_sessions,
        total_count,
        waiting_count,
    }
}
