//! Data structures for Codex conversation parsing.

use serde::Deserialize;

/// A single line in a Codex JSONL session file.
#[derive(Deserialize)]
pub struct CodexJsonlLine {
    #[serde(rename = "type")]
    pub line_type: String,
    pub payload: Option<CodexPayload>,
}

/// Payload for a JSONL line.
#[derive(Deserialize)]
pub struct CodexPayload {
    #[serde(rename = "type")]
    pub payload_type: Option<String>,
    pub role: Option<String>,
    pub content: Option<Vec<CodexContent>>,
    /// For event_msg type
    pub message: Option<String>,
}

/// Content within a Codex conversation item.
#[derive(Deserialize)]
pub struct CodexContent {
    #[serde(rename = "type")]
    pub content_type: String,
    pub text: Option<String>,
}
