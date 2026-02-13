//! Command handlers for Tauri commands
//!
//! This module contains all the Tauri command handlers, organized into submodules:
//! - `session`: Session-related commands (get_all_sessions, focus_session)
//! - `tray`: Tray icon commands (update_tray_title)
//! - `shortcut`: Global keyboard shortcut commands (register/unregister)
//! - `process`: Process management commands (kill_session)
//! - `editor`: Editor and terminal commands (open_in_editor, open_in_terminal)
//! - `debug`: Debug utilities (write_debug_log)
//! - `notification_*`: Voice notification system commands
//! - `bell_mode`: Bell mode notification commands

mod bell_mode;
mod debug;
mod editor;
mod mini_viewer;
mod notification_check;
mod notification_install;
mod notification_scripts;
mod notification_uninstall;
mod notification_utils;
mod process;
mod session;
mod shortcut;
mod tray;

// Re-export all public command handlers
pub use bell_mode::{check_bell_mode, set_bell_mode};
pub use debug::write_debug_log;
pub use editor::{open_in_editor, open_in_terminal, run_project_command};
pub use mini_viewer::{
    register_mini_viewer_shortcut, set_mini_viewer_experimental_vscode_session_opening,
    set_mini_viewer_side, show_mini_viewer, shutdown_mini_viewer, unregister_mini_viewer_shortcut,
};
pub use notification_check::check_notification_system;
pub use notification_install::install_notification_system;
pub use notification_uninstall::uninstall_notification_system;
pub use process::kill_session;
pub use session::{focus_session, get_all_sessions, get_project_git_diff_stats};
pub use shortcut::{register_shortcut, unregister_shortcut};
pub use tray::update_tray_title;
