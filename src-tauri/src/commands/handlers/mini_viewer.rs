//! Native mini viewer command handlers (macOS)

#[cfg(target_os = "macos")]
mod macos {
    use crate::session::{AgentType, Session, SessionStatus};
    use serde::{Deserialize, Serialize};
    use std::{
        collections::HashMap,
        fs,
        io::{BufRead, BufReader, BufWriter, Write},
        path::PathBuf,
        process::{Child, ChildStdin, ChildStdout, Command, Stdio},
        sync::{LazyLock, Mutex},
        thread::{self, JoinHandle},
        time::{Duration, Instant},
    };
    use tauri::{path::BaseDirectory, Manager};
    use tauri_plugin_global_shortcut::{GlobalShortcutExt, Shortcut};

    static CURRENT_MINI_VIEWER_SHORTCUT: Mutex<Option<Shortcut>> = Mutex::new(None);
    static MINI_VIEWER_STATE: Mutex<MiniViewerState> = Mutex::new(MiniViewerState::new());
    static MINI_VIEWER_DIFF_CACHE: LazyLock<Mutex<HashMap<String, CachedGitDiffStats>>> =
        LazyLock::new(|| Mutex::new(HashMap::new()));

    const MINI_VIEWER_DIFF_CACHE_TTL: Duration = Duration::from_secs(12);

    #[derive(Debug, Clone, Copy, PartialEq, Eq)]
    enum MiniViewerSide {
        Left,
        Right,
    }

    impl MiniViewerSide {
        fn from_str(value: &str) -> Option<Self> {
            match value.trim().to_lowercase().as_str() {
                "left" => Some(Self::Left),
                "right" => Some(Self::Right),
                _ => None,
            }
        }

        fn as_str(self) -> &'static str {
            match self {
                Self::Left => "left",
                Self::Right => "right",
            }
        }
    }

    struct MiniViewerState {
        side: MiniViewerSide,
        experimental_vscode_session_opening: bool,
        process: Option<Child>,
        updater: Option<JoinHandle<()>>,
        listener: Option<JoinHandle<()>>,
    }

    impl MiniViewerState {
        const fn new() -> Self {
            Self {
                side: MiniViewerSide::Right,
                experimental_vscode_session_opening: false,
                process: None,
                updater: None,
                listener: None,
            }
        }
    }

    #[derive(Debug, Clone, Copy)]
    struct CachedGitDiffStats {
        additions: u64,
        deletions: u64,
        fetched_at: Instant,
    }

    #[derive(Debug, Clone, Serialize)]
    #[serde(rename_all = "camelCase")]
    struct MiniViewerSession {
        id: String,
        agent_type: AgentType,
        project_name: String,
        project_path: String,
        status: SessionStatus,
        last_message: Option<String>,
        last_activity_at: String,
        pid: u32,
        cpu_usage: f32,
        memory_bytes: u64,
        active_subagent_count: usize,
    }

    #[derive(Debug, Clone, Serialize)]
    #[serde(rename_all = "camelCase")]
    struct MiniViewerProject {
        project_name: String,
        project_path: String,
        git_branch: Option<String>,
        diff_additions: u64,
        diff_deletions: u64,
        sessions: Vec<MiniViewerSession>,
    }

    impl From<Session> for MiniViewerSession {
        fn from(session: Session) -> Self {
            Self {
                id: session.id,
                agent_type: session.agent_type,
                project_name: session.project_name,
                project_path: session.project_path,
                status: session.status,
                last_message: session.last_message,
                last_activity_at: session.last_activity_at,
                pid: session.pid,
                cpu_usage: session.cpu_usage,
                memory_bytes: session.memory_bytes,
                active_subagent_count: session.active_subagent_count,
            }
        }
    }

    #[derive(Serialize)]
    #[serde(rename_all = "camelCase")]
    struct MiniViewerPayload {
        side: String,
        projects: Vec<MiniViewerProject>,
    }

    #[derive(Debug, Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct MiniViewerAction {
        action: String,
        pid: u32,
        project_path: String,
        project_name: String,
    }

    fn normalized_branch(branch: Option<String>) -> Option<String> {
        branch.and_then(|value| {
            let trimmed = value.trim();
            if trimmed.is_empty() {
                None
            } else {
                Some(trimmed.to_string())
            }
        })
    }

    fn project_git_diff_stats(project_path: &str) -> (u64, u64) {
        let now = Instant::now();
        if let Some(cached) = MINI_VIEWER_DIFF_CACHE
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .get(project_path)
            .copied()
        {
            if now.duration_since(cached.fetched_at) < MINI_VIEWER_DIFF_CACHE_TTL {
                return (cached.additions, cached.deletions);
            }
        }

        let stats = crate::commands::get_project_git_diff_stats(project_path.to_string())
            .unwrap_or_default();
        let additions = stats.additions;
        let deletions = stats.deletions;

        MINI_VIEWER_DIFF_CACHE
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .insert(
                project_path.to_string(),
                CachedGitDiffStats {
                    additions,
                    deletions,
                    fetched_at: now,
                },
            );

        (additions, deletions)
    }

    fn collect_visible_projects() -> Vec<MiniViewerProject> {
        let response = crate::session::get_sessions();
        let visible = if response.background_sessions.is_empty() {
            response
                .sessions
                .into_iter()
                .filter(|session| !session.is_background)
                .collect::<Vec<_>>()
        } else {
            response.sessions
        };

        let mut projects = Vec::<MiniViewerProject>::new();
        let mut project_index_by_path = HashMap::<String, usize>::new();

        for session in visible {
            let project_path = session.project_path.clone();
            let branch = normalized_branch(session.git_branch.clone());
            let mini_session = MiniViewerSession::from(session);

            let index = if let Some(existing) = project_index_by_path.get(&project_path) {
                *existing
            } else {
                let new_index = projects.len();
                projects.push(MiniViewerProject {
                    project_name: mini_session.project_name.clone(),
                    project_path: project_path.clone(),
                    git_branch: branch.clone(),
                    diff_additions: 0,
                    diff_deletions: 0,
                    sessions: Vec::new(),
                });
                project_index_by_path.insert(project_path.clone(), new_index);
                new_index
            };

            let project = &mut projects[index];
            if project.git_branch.is_none() {
                project.git_branch = branch;
            }
            project.sessions.push(mini_session);
        }

        for project in &mut projects {
            let (additions, deletions) = project_git_diff_stats(&project.project_path);
            project.diff_additions = additions;
            project.diff_deletions = deletions;
        }

        projects
    }

    fn current_side() -> MiniViewerSide {
        MINI_VIEWER_STATE
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .side
    }

    fn spawn_updater_thread(app: tauri::AppHandle, stdin: ChildStdin) -> JoinHandle<()> {
        thread::spawn(move || {
            let mut writer = BufWriter::new(stdin);

            loop {
                let payload = MiniViewerPayload {
                    side: current_side().as_str().to_string(),
                    projects: collect_visible_projects(),
                };

                let write_result = serde_json::to_writer(&mut writer, &payload)
                    .map_err(|_| ())
                    .and_then(|_| writer.write_all(b"\n").map_err(|_| ()))
                    .and_then(|_| writer.flush().map_err(|_| ()));

                if write_result.is_err() {
                    break;
                }

                // Keep the mini viewer live and up to date without tying it to the webview lifecycle.
                thread::sleep(Duration::from_secs(3));

                if app.get_webview_window("main").is_none() {
                    break;
                }
            }
        })
    }

    fn handle_action(action: MiniViewerAction) {
        match action.action.as_str() {
            "focusSession" => {
                let use_experimental = MINI_VIEWER_STATE
                    .lock()
                    .unwrap_or_else(|e| e.into_inner())
                    .experimental_vscode_session_opening;

                if crate::commands::open_in_editor(
                    action.project_path.clone(),
                    "code".to_string(),
                    Some(use_experimental),
                    Some(action.project_name.clone()),
                )
                .is_ok()
                {
                    return;
                }

                if crate::commands::focus_session(action.pid, action.project_path.clone()).is_ok() {
                    return;
                }

                let _ =
                    crate::commands::open_in_terminal(action.project_path, "terminal".to_string());
            }
            "endSession" => {
                let _ = crate::commands::kill_session(action.pid);
            }
            _ => {}
        }
    }

    fn spawn_listener_thread(stdout: ChildStdout) -> JoinHandle<()> {
        thread::spawn(move || {
            let reader = BufReader::new(stdout);
            for line in reader.lines() {
                let Ok(content) = line else {
                    break;
                };
                if content.trim().is_empty() {
                    continue;
                }

                if let Ok(action) = serde_json::from_str::<MiniViewerAction>(&content) {
                    handle_action(action);
                }
            }
        })
    }

    fn mini_viewer_source_path(app: &tauri::AppHandle) -> Result<PathBuf, String> {
        let resource_path = app
            .path()
            .resolve(
                "native-mini-viewer/MiniViewer.swift",
                BaseDirectory::Resource,
            )
            .ok();

        if let Some(path) = resource_path {
            if path.exists() {
                return Ok(path);
            }
        }

        let dev_path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("native-mini-viewer")
            .join("MiniViewer.swift");

        if dev_path.exists() {
            return Ok(dev_path);
        }

        Err("Mini viewer Swift source not found".to_string())
    }

    fn mini_viewer_icon_dir(app: &tauri::AppHandle) -> Result<PathBuf, String> {
        let source = mini_viewer_source_path(app)?;
        let icon_dir = source
            .parent()
            .ok_or_else(|| "Mini viewer source has no parent directory".to_string())?
            .join("icons");

        if icon_dir.exists() {
            Ok(icon_dir)
        } else {
            Err("Mini viewer icon directory not found".to_string())
        }
    }

    fn mini_viewer_binary_path(app: &tauri::AppHandle) -> Result<PathBuf, String> {
        let source = mini_viewer_source_path(app)?;
        let app_data_dir = app
            .path()
            .app_data_dir()
            .map_err(|e| format!("Failed to resolve app data directory: {}", e))?;

        let output_dir = app_data_dir.join("native-mini-viewer");
        fs::create_dir_all(&output_dir)
            .map_err(|e| format!("Failed to create mini viewer output directory: {}", e))?;

        let output_binary = output_dir.join("mini-viewer-helper");

        let source_mtime = fs::metadata(&source).and_then(|m| m.modified()).ok();
        let binary_mtime = fs::metadata(&output_binary).and_then(|m| m.modified()).ok();
        let needs_rebuild = !output_binary.exists() || source_mtime > binary_mtime;

        if needs_rebuild {
            let status = Command::new("xcrun")
                .arg("swiftc")
                .arg("-O")
                .arg(&source)
                .arg("-o")
                .arg(&output_binary)
                .status()
                .map_err(|e| format!("Failed to launch Swift compiler for mini viewer: {}", e))?;

            if !status.success() {
                return Err(
                    "Failed to compile native mini viewer (swiftc exited with an error)"
                        .to_string(),
                );
            }
        }

        Ok(output_binary)
    }

    fn start_mini_viewer(app: &tauri::AppHandle) -> Result<(), String> {
        let (existing_updater, existing_listener) = {
            let mut state = MINI_VIEWER_STATE.lock().unwrap_or_else(|e| e.into_inner());

            if let Some(child) = state.process.as_mut() {
                match child.try_wait() {
                    Ok(None) => return Ok(()),
                    _ => {
                        state.process = None;
                        (state.updater.take(), state.listener.take())
                    }
                }
            } else {
                (None, None)
            }
        };

        if let Some(handle) = existing_updater {
            let _ = handle.join();
        }
        if let Some(handle) = existing_listener {
            let _ = handle.join();
        }

        let binary = mini_viewer_binary_path(app)?;
        let icon_dir = mini_viewer_icon_dir(app)?;

        let mut child = Command::new(&binary)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .env("MINI_VIEWER_ICON_DIR", icon_dir)
            .spawn()
            .map_err(|e| format!("Failed to spawn native mini viewer: {}", e))?;

        let stdin = child
            .stdin
            .take()
            .ok_or_else(|| "Failed to open mini viewer stdin".to_string())?;
        let stdout = child
            .stdout
            .take()
            .ok_or_else(|| "Failed to open mini viewer stdout".to_string())?;

        let updater = spawn_updater_thread(app.clone(), stdin);
        let listener = spawn_listener_thread(stdout);

        let mut state = MINI_VIEWER_STATE.lock().unwrap_or_else(|e| e.into_inner());
        state.process = Some(child);
        state.updater = Some(updater);
        state.listener = Some(listener);

        Ok(())
    }

    fn stop_mini_viewer() {
        let (mut child, updater, listener) = {
            let mut state = MINI_VIEWER_STATE.lock().unwrap_or_else(|e| e.into_inner());
            (
                state.process.take(),
                state.updater.take(),
                state.listener.take(),
            )
        };

        if let Some(running_child) = child.as_mut() {
            let _ = running_child.kill();
            let _ = running_child.wait();
        }

        if let Some(handle) = updater {
            let _ = handle.join();
        }
        if let Some(handle) = listener {
            let _ = handle.join();
        }
    }

    fn is_mini_viewer_running() -> bool {
        let mut state = MINI_VIEWER_STATE.lock().unwrap_or_else(|e| e.into_inner());

        if let Some(child) = state.process.as_mut() {
            match child.try_wait() {
                Ok(None) => true,
                _ => {
                    state.process = None;
                    state.updater = None;
                    state.listener = None;
                    false
                }
            }
        } else {
            false
        }
    }

    fn toggle_mini_viewer(app: &tauri::AppHandle) -> Result<(), String> {
        if is_mini_viewer_running() {
            stop_mini_viewer();
            Ok(())
        } else {
            start_mini_viewer(app)
        }
    }

    #[tauri::command]
    pub fn register_mini_viewer_shortcut(
        app: tauri::AppHandle,
        shortcut: String,
    ) -> Result<(), String> {
        if let Some(old_shortcut) = CURRENT_MINI_VIEWER_SHORTCUT
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .take()
        {
            let _ = app.global_shortcut().unregister(old_shortcut);
        }

        let parsed_shortcut: Shortcut = shortcut
            .parse()
            .map_err(|e| format!("Invalid mini viewer shortcut format: {}", e))?;

        app.global_shortcut()
            .on_shortcut(parsed_shortcut.clone(), move |app, _shortcut, event| {
                if event.state != tauri_plugin_global_shortcut::ShortcutState::Pressed {
                    return;
                }

                if let Err(err) = toggle_mini_viewer(app) {
                    eprintln!("mini viewer toggle failed: {}", err);
                }
            })
            .map_err(|e| format!("Failed to register mini viewer shortcut: {}", e))?;

        *CURRENT_MINI_VIEWER_SHORTCUT
            .lock()
            .unwrap_or_else(|e| e.into_inner()) = Some(parsed_shortcut);

        Ok(())
    }

    #[tauri::command]
    pub fn unregister_mini_viewer_shortcut(app: tauri::AppHandle) -> Result<(), String> {
        if let Some(shortcut) = CURRENT_MINI_VIEWER_SHORTCUT
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .take()
        {
            app.global_shortcut()
                .unregister(shortcut)
                .map_err(|e| format!("Failed to unregister mini viewer shortcut: {}", e))?;
        }

        stop_mini_viewer();
        Ok(())
    }

    #[tauri::command]
    pub fn set_mini_viewer_side(side: String) -> Result<(), String> {
        let parsed = MiniViewerSide::from_str(&side)
            .ok_or_else(|| "Mini viewer side must be 'left' or 'right'".to_string())?;

        MINI_VIEWER_STATE
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .side = parsed;

        Ok(())
    }

    #[tauri::command]
    pub fn set_mini_viewer_experimental_vscode_session_opening(
        enabled: bool,
    ) -> Result<(), String> {
        MINI_VIEWER_STATE
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .experimental_vscode_session_opening = enabled;
        Ok(())
    }

    #[tauri::command]
    pub fn show_mini_viewer(app: tauri::AppHandle) -> Result<(), String> {
        start_mini_viewer(&app)
    }

    pub fn shutdown_mini_viewer() {
        stop_mini_viewer();
    }

    pub use register_mini_viewer_shortcut as register_shortcut;
    pub use set_mini_viewer_experimental_vscode_session_opening as set_experimental_vscode_session_opening;
    pub use set_mini_viewer_side as set_side;
    pub use show_mini_viewer as show;
    pub use unregister_mini_viewer_shortcut as unregister_shortcut;
}

#[cfg(not(target_os = "macos"))]
mod macos {
    #[tauri::command]
    pub fn register_shortcut(_app: tauri::AppHandle, _shortcut: String) -> Result<(), String> {
        Err("Mini viewer is only supported on macOS".to_string())
    }

    #[tauri::command]
    pub fn unregister_shortcut(_app: tauri::AppHandle) -> Result<(), String> {
        Ok(())
    }

    #[tauri::command]
    pub fn set_side(_side: String) -> Result<(), String> {
        Err("Mini viewer is only supported on macOS".to_string())
    }

    #[tauri::command]
    pub fn set_experimental_vscode_session_opening(_enabled: bool) -> Result<(), String> {
        Err("Mini viewer is only supported on macOS".to_string())
    }

    #[tauri::command]
    pub fn show(_app: tauri::AppHandle) -> Result<(), String> {
        Err("Mini viewer is only supported on macOS".to_string())
    }

    pub fn shutdown_mini_viewer() {}
}

pub use macos::register_shortcut as register_mini_viewer_shortcut;
pub use macos::set_experimental_vscode_session_opening as set_mini_viewer_experimental_vscode_session_opening;
pub use macos::set_side as set_mini_viewer_side;
pub use macos::show as show_mini_viewer;
pub use macos::shutdown_mini_viewer;
pub use macos::unregister_shortcut as unregister_mini_viewer_shortcut;
