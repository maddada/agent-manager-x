//! OpenCode agent detection and session parsing
//!
//! This module handles detection of running OpenCode processes and
//! parsing their session data from the storage directory.

mod builder;
mod message;
mod process;
mod project;
mod session;
mod types;

use crate::agent::{AgentDetector, AgentProcess};
use crate::session::{AgentType, Session};

pub use process::find_opencode_processes;
pub use session::get_opencode_sessions;
pub use types::*;

/// Detector for OpenCode agent sessions
pub struct OpenCodeDetector;

impl AgentDetector for OpenCodeDetector {
    fn name(&self) -> &'static str {
        "OpenCode"
    }

    fn agent_type(&self) -> AgentType {
        AgentType::OpenCode
    }

    fn find_processes(&self) -> Vec<AgentProcess> {
        find_opencode_processes()
    }

    fn find_sessions(&self, processes: &[AgentProcess]) -> Vec<Session> {
        if processes.is_empty() {
            return Vec::new();
        }
        get_opencode_sessions(processes)
    }
}
