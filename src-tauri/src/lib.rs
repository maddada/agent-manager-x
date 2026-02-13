#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

pub mod agent;
pub mod commands;
pub mod logging;
pub mod process;
pub mod session;
pub mod terminal;

#[cfg(test)]
mod tests;

use std::sync::Mutex;
use tauri::{
    menu::{MenuBuilder, MenuItemBuilder},
    tray::TrayIconBuilder,
    Manager,
};

use commands::{
    check_bell_mode, check_notification_system, focus_session, get_all_sessions,
    get_project_git_diff_stats, install_notification_system, kill_session, open_in_editor,
    open_in_terminal, register_mini_viewer_shortcut, register_shortcut, run_project_command,
    set_bell_mode, set_mini_viewer_experimental_vscode_session_opening, set_mini_viewer_side,
    show_mini_viewer, shutdown_mini_viewer, uninstall_notification_system,
    unregister_mini_viewer_shortcut, unregister_shortcut, update_tray_title, write_debug_log,
};

// Store tray icon ID for updates
static TRAY_ID: Mutex<Option<String>> = Mutex::new(None);

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    // Initialize logging (only active in debug builds)
    let _ = logging::init();

    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .plugin(tauri_plugin_window_state::Builder::default().build())
        .invoke_handler(tauri::generate_handler![
            get_all_sessions,
            focus_session,
            get_project_git_diff_stats,
            update_tray_title,
            register_shortcut,
            unregister_shortcut,
            register_mini_viewer_shortcut,
            unregister_mini_viewer_shortcut,
            set_mini_viewer_side,
            set_mini_viewer_experimental_vscode_session_opening,
            show_mini_viewer,
            kill_session,
            open_in_editor,
            open_in_terminal,
            run_project_command,
            write_debug_log,
            check_notification_system,
            install_notification_system,
            uninstall_notification_system,
            check_bell_mode,
            set_bell_mode
        ])
        .setup(|app| {
            #[cfg(target_os = "macos")]
            {
                // Ensure the app is treated as a regular, dock-visible application
                // so window switchers (e.g., DockDoor) can detect it.
                app.set_activation_policy(tauri::ActivationPolicy::Regular);
                app.set_dock_visibility(true);
            }

            // Create menu for tray
            let show_item = MenuItemBuilder::with_id("show", "Show Window").build(app)?;
            let quit_item = MenuItemBuilder::with_id("quit", "Quit").build(app)?;

            let menu = MenuBuilder::new(app)
                .item(&show_item)
                .separator()
                .item(&quit_item)
                .build()?;

            // Create tray icon with menu
            // Use include_bytes to embed tray icon at compile time
            let tray_icon =
                tauri::image::Image::from_bytes(include_bytes!("../icons/tray-icon.png"))
                    .unwrap_or_else(|_| app.default_window_icon().unwrap().clone());
            let _tray = TrayIconBuilder::with_id("main-tray")
                .icon(tray_icon)
                .icon_as_template(true)
                .menu(&menu)
                .show_menu_on_left_click(false)
                .on_menu_event(|app, event| match event.id().as_ref() {
                    "show" => {
                        if let Some(window) = app.get_webview_window("main") {
                            let _ = window.show();
                            let _ = window.set_focus();
                        }
                    }
                    "quit" => {
                        app.exit(0);
                    }
                    _ => {}
                })
                .on_tray_icon_event(|tray, event| {
                    if let tauri::tray::TrayIconEvent::Click {
                        button: tauri::tray::MouseButton::Left,
                        ..
                    } = event
                    {
                        let app = tray.app_handle();
                        if let Some(window) = app.get_webview_window("main") {
                            let _ = window.show();
                            let _ = window.set_focus();
                        }
                    }
                })
                .build(app)?;

            // Store tray ID
            *TRAY_ID.lock().unwrap_or_else(|e| e.into_inner()) = Some("main-tray".to_string());

            Ok(())
        })
        .on_window_event(|window, event| {
            // Handle dock icon click by showing window when activated
            if let tauri::WindowEvent::Focused(true) = event {
                let _ = window.show();
            }
        })
        .build(tauri::generate_context!())
        .expect("error while building tauri application")
        .run(|_app, _event| match _event {
            tauri::RunEvent::Exit => {
                shutdown_mini_viewer();
            }
            // Handle dock icon click when app is already running (macOS only)
            #[cfg(target_os = "macos")]
            tauri::RunEvent::Reopen {
                has_visible_windows,
                ..
            } => {
                if !has_visible_windows {
                    if let Some(window) = _app.get_webview_window("main") {
                        let _ = window.show();
                        let _ = window.set_focus();
                    }
                }
            }
            _ => {}
        });
}
