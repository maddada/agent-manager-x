//! Codex agent detection and session management.
//!
//! This module provides functionality for detecting running Codex processes
//! and parsing their session data.

mod process;
mod session;
mod types;

pub use process::find_codex_processes;
pub use session::get_codex_sessions;
pub use types::{CodexContent, CodexJsonlLine, CodexPayload};

use super::{AgentDetector, AgentProcess};
use crate::session::{AgentType, Session};

/// Detector for Codex agent sessions.
pub struct CodexDetector;

impl AgentDetector for CodexDetector {
    fn name(&self) -> &'static str {
        "Codex"
    }

    fn agent_type(&self) -> AgentType {
        AgentType::Codex
    }

    fn find_processes(&self) -> Vec<AgentProcess> {
        find_codex_processes()
    }

    fn find_sessions(&self, processes: &[AgentProcess]) -> Vec<Session> {
        if processes.is_empty() {
            return Vec::new();
        }
        get_codex_sessions(processes)
    }
}
