//! Data structures for OpenCode JSON files

use serde::Deserialize;

/// OpenCode project definition from storage/project/*.json
#[derive(Deserialize)]
pub struct OpenCodeProject {
    pub id: String,
    pub worktree: String,
    #[serde(default)]
    pub sandboxes: Vec<String>,
    #[serde(default)]
    pub time: OpenCodeTime,
}

/// Timestamp information used across OpenCode entities
#[derive(Deserialize, Default)]
pub struct OpenCodeTime {
    #[serde(default)]
    pub created: u64,
    #[serde(default)]
    pub updated: u64,
}

/// OpenCode session from storage/session/{project_id}/*.json
#[derive(Deserialize)]
pub struct OpenCodeSession {
    pub id: String,
    #[serde(rename = "projectID")]
    pub project_id: String,
    #[serde(default)]
    pub directory: String,
    #[serde(default)]
    pub title: String,
    #[serde(default)]
    pub time: OpenCodeTime,
}

/// OpenCode message from storage/message/{session_id}/*.json
#[derive(Deserialize)]
pub struct OpenCodeMessage {
    pub id: String,
    #[serde(rename = "sessionID")]
    pub session_id: String,
    pub role: String,
    #[serde(default)]
    pub time: OpenCodeTime,
}

/// OpenCode message part from storage/part/{message_id}/*.json
#[derive(Deserialize)]
pub struct OpenCodePart {
    #[serde(rename = "type")]
    pub part_type: String,
    #[serde(default)]
    pub text: Option<String>,
}
