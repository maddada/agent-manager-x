//! Session parsing module.
//!
//! This module handles parsing of JSONL session files and discovering active sessions.
//!
//! # Submodules
//!
//! - `utils`: Utility functions for content preview and GitHub URL extraction
//! - `path_conversion`: Conversion between file system paths and directory names
//! - `subagent`: Subagent detection and counting
//! - `jsonl_files`: JSONL file discovery and session matching
//! - `message_extraction`: Message data extraction from JSONL lines
//! - `session_parser`: Core session file parsing logic
//! - `sessions`: Main session discovery and aggregation

mod jsonl_files;
mod message_extraction;
mod path_conversion;
mod session_parser;
mod sessions;
mod subagent;
mod utils;

// Re-export public API
pub use path_conversion::{convert_dir_name_to_path, convert_path_to_dir_name};
pub use session_parser::parse_session_file;
pub use sessions::{get_sessions, get_sessions_internal};
