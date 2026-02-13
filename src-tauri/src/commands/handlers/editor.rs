//! Editor and terminal command handlers

#[cfg(target_os = "macos")]
use core_foundation::{
    array::{CFArray, CFArrayRef},
    base::{CFType, CFTypeRef, TCFType},
    boolean::CFBoolean,
    data::CFData,
    dictionary::{CFDictionary, CFDictionaryRef},
    number::CFNumber,
    string::CFString,
};
#[cfg(target_os = "macos")]
use core_graphics::window::{self, kCGNullWindowID, CGWindowID};
#[cfg(target_os = "macos")]
use libloading::os::unix::Library as UnixLibrary;
#[cfg(target_os = "macos")]
use libloading::Library;
#[cfg(target_os = "macos")]
use once_cell::sync::Lazy;
#[cfg(target_os = "macos")]
use std::path::Path;
use std::process::Command;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{Duration, Instant};
#[cfg(target_os = "macos")]
use std::{collections::HashSet, ffi::c_void};

static SWITCH_ATTEMPT_COUNTER: AtomicU64 = AtomicU64::new(1);

/// Get the full PATH from the user's login shell.
/// Bundled macOS apps inherit a minimal PATH (/usr/bin:/bin:/usr/sbin:/sbin),
/// so editor CLIs installed via Homebrew or app installers won't be found.
/// We resolve this by asking the login shell for its PATH, with static extras as fallback.
fn enriched_path() -> String {
    // Try to get the full PATH from the user's default login shell
    if let Ok(output) = Command::new("/bin/zsh")
        .args(["-l", "-c", "echo $PATH"])
        .output()
    {
        let shell_path = String::from_utf8_lossy(&output.stdout).trim().to_string();
        if !shell_path.is_empty() {
            return shell_path;
        }
    }

    // Fallback: prepend common locations to the current PATH
    let base = std::env::var("PATH").unwrap_or_default();
    let home = std::env::var("HOME").unwrap_or_default();
    let mut parts = vec![
        "/usr/local/bin".to_string(),
        "/opt/homebrew/bin".to_string(),
        "/opt/homebrew/sbin".to_string(),
    ];
    if !home.is_empty() {
        parts.push(format!("{}/.local/bin", home));
    }
    if !base.is_empty() {
        parts.push(base);
    }
    parts.join(":")
}

#[cfg(target_os = "macos")]
#[repr(C)]
struct ProcessSerialNumber {
    high_long_of_psn: u32,
    low_long_of_psn: u32,
}

#[cfg(target_os = "macos")]
#[link(name = "ApplicationServices", kind = "framework")]
unsafe extern "C" {
    fn GetProcessForPID(pid: i32, psn: *mut ProcessSerialNumber) -> i32;
    fn AXUIElementCreateApplication(pid: i32) -> *const c_void;
    fn AXUIElementCopyAttributeValue(
        element: *const c_void,
        attribute: *const c_void,
        value: *mut CFTypeRef,
    ) -> i32;
    fn AXUIElementPerformAction(element: *const c_void, action: *const c_void) -> i32;
    fn AXUIElementSetAttributeValue(
        element: *const c_void,
        attribute: *const c_void,
        value: CFTypeRef,
    ) -> i32;
    fn _AXUIElementGetWindow(element: *const c_void, window_id: *mut CGWindowID) -> i32;
    fn _AXUIElementCreateWithRemoteToken(token: *const c_void) -> *const c_void;
}

#[cfg(target_os = "macos")]
type SLPSSetFrontProcessWithOptions =
    unsafe extern "C" fn(psn: *mut ProcessSerialNumber, wid: CGWindowID, mode: u32) -> i32;

#[cfg(target_os = "macos")]
type SLPSPostEventRecordTo =
    unsafe extern "C" fn(psn: *mut ProcessSerialNumber, bytes: *mut u8) -> i32;

#[cfg(target_os = "macos")]
type CGSMainConnectionID = unsafe extern "C" fn() -> u32;

#[cfg(target_os = "macos")]
type CGSCopyWindowProperty = unsafe extern "C" fn(
    connection_id: u32,
    window_id: u32,
    key: *const std::ffi::c_void,
    out_value: *mut CFTypeRef,
) -> i32;

#[cfg(target_os = "macos")]
struct SkyLightApi {
    _lib: Library,
    set_front_process: SLPSSetFrontProcessWithOptions,
    post_event_record: SLPSPostEventRecordTo,
    cgs_main_connection_id: Option<CGSMainConnectionID>,
    cgs_copy_window_property: Option<CGSCopyWindowProperty>,
}

#[cfg(target_os = "macos")]
#[derive(Clone, Debug)]
struct WindowMatch {
    pid: i32,
    window_id: CGWindowID,
    title: String,
    match_kind: &'static str,
    is_on_screen: bool,
}

fn shorten_for_log(input: &str, max_len: usize) -> String {
    if input.len() <= max_len {
        return input.to_string();
    }
    let keep = max_len.saturating_sub(3);
    format!("{}...", &input[..keep])
}

#[cfg(target_os = "macos")]
static SKYLIGHT_API: Lazy<Option<SkyLightApi>> = Lazy::new(|| unsafe {
    let try_load = |lib: Library| {
        let set_front = *lib
            .get::<SLPSSetFrontProcessWithOptions>(b"_SLPSSetFrontProcessWithOptions")
            .ok()?;
        let post_event = *lib
            .get::<SLPSPostEventRecordTo>(b"SLPSPostEventRecordTo")
            .ok()?;
        let mut cgs_main_connection_id = lib
            .get::<CGSMainConnectionID>(b"CGSMainConnectionID")
            .ok()
            .map(|symbol| *symbol);
        let mut cgs_copy_window_property = lib
            .get::<CGSCopyWindowProperty>(b"CGSCopyWindowProperty")
            .ok()
            .map(|symbol| *symbol);

        // Some macOS builds expose these via global symbols instead of the framework image.
        if cgs_main_connection_id.is_none() || cgs_copy_window_property.is_none() {
            let global: Library = UnixLibrary::this().into();
            if cgs_main_connection_id.is_none() {
                cgs_main_connection_id = global
                    .get::<CGSMainConnectionID>(b"CGSMainConnectionID")
                    .ok()
                    .map(|symbol| *symbol);
            }
            if cgs_copy_window_property.is_none() {
                cgs_copy_window_property = global
                    .get::<CGSCopyWindowProperty>(b"CGSCopyWindowProperty")
                    .ok()
                    .map(|symbol| *symbol);
            }
        }
        Some(SkyLightApi {
            _lib: lib,
            set_front_process: set_front,
            post_event_record: post_event,
            cgs_main_connection_id,
            cgs_copy_window_property,
        })
    };

    if let Ok(path_lib) =
        Library::new("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight")
    {
        if let Some(api) = try_load(path_lib) {
            log::info!(
                target: "editor.switch",
                "Loaded SkyLight private APIs from framework path (cgs_title_support={})",
                api.cgs_main_connection_id.is_some() && api.cgs_copy_window_property.is_some()
            );
            return Some(api);
        }
        log::warn!(
            target: "editor.switch",
            "SkyLight framework path loaded but required symbols were missing"
        );
    } else {
        log::warn!(
            target: "editor.switch",
            "Failed to load SkyLight from framework path, trying global symbol lookup"
        );
    }

    // On newer macOS versions the SkyLight binary can live only in dyld shared cache.
    // Fallback to global symbol lookup through the current process image.
    let fallback = try_load(UnixLibrary::this().into());
    if fallback.is_some() {
        log::info!(
            target: "editor.switch",
            "Loaded SkyLight private APIs from global symbol table (cgs_title_support={})",
            fallback
                .as_ref()
                .is_some_and(|api| api.cgs_main_connection_id.is_some() && api.cgs_copy_window_property.is_some())
        );
    } else {
        log::error!(
            target: "editor.switch",
            "Unable to resolve SkyLight private API symbols"
        );
    }
    fallback
});

#[cfg(target_os = "macos")]
fn make_project_hints(path: &str, project_name: Option<&str>) -> Vec<String> {
    let path_obj = Path::new(path);
    let mut hints: Vec<String> = Vec::new();

    if let Some(project_name) = project_name {
        let trimmed = project_name.trim();
        if !trimmed.is_empty() {
            hints.push(trimmed.to_ascii_lowercase());
        }
    }

    if let Some(name) = path_obj.file_name().and_then(|v| v.to_str()) {
        hints.push(name.to_ascii_lowercase());
    }
    if let Some(stem) = path_obj.file_stem().and_then(|v| v.to_str()) {
        hints.push(stem.to_ascii_lowercase());
    }
    if let Some(parent) = path_obj
        .parent()
        .and_then(|v| v.file_name())
        .and_then(|v| v.to_str())
    {
        hints.push(parent.to_ascii_lowercase());
    }

    hints.retain(|hint| hint.len() > 1);
    hints.sort_unstable();
    hints.dedup();
    hints
}

#[cfg(target_os = "macos")]
fn is_vscode_owner(owner_name: &str) -> bool {
    let owner = owner_name.to_ascii_lowercase();
    owner == "code"
        || owner == "visual studio code"
        || owner == "code - insiders"
        || owner.contains("visual studio code")
}

#[cfg(target_os = "macos")]
fn dict_i64(dict: &CFDictionary<CFString, CFType>, key: &CFString) -> Option<i64> {
    dict.find(key)
        .and_then(|value| value.downcast::<CFNumber>())
        .and_then(|value| value.to_i64())
}

#[cfg(target_os = "macos")]
fn dict_string(dict: &CFDictionary<CFString, CFType>, key: &CFString) -> Option<String> {
    dict.find(key)
        .and_then(|value| value.downcast::<CFString>())
        .map(|value| value.to_string())
}

#[cfg(target_os = "macos")]
fn dict_bool(dict: &CFDictionary<CFString, CFType>, key: &CFString) -> Option<bool> {
    dict.find(key)
        .and_then(|value| value.downcast::<CFBoolean>())
        .map(|value| bool::from(value.clone()))
}

#[cfg(target_os = "macos")]
fn project_match_priority(title: &str, project_name: &str) -> Option<i32> {
    if title == project_name {
        return Some(5);
    }
    if title.starts_with(project_name) {
        return Some(4);
    }
    if title.contains(&format!(" - {}", project_name))
        || title.contains(&format!(" — {}", project_name))
        || title.contains(&format!(" {} ", project_name))
    {
        return Some(3);
    }
    if title.contains(project_name) {
        return Some(2);
    }
    None
}

#[cfg(target_os = "macos")]
fn cgs_window_title(window_id: CGWindowID) -> Option<String> {
    let api = SKYLIGHT_API.as_ref()?;
    let connection_fn = api.cgs_main_connection_id?;
    let copy_property_fn = api.cgs_copy_window_property?;

    let connection_id = unsafe { connection_fn() };
    let key = CFString::new("kCGSWindowTitle");
    let mut value: CFTypeRef = std::ptr::null();
    let status = unsafe {
        copy_property_fn(
            connection_id,
            window_id,
            key.as_concrete_TypeRef() as *const std::ffi::c_void,
            &mut value,
        )
    };
    if status != 0 || value.is_null() {
        return None;
    }

    unsafe { CFType::wrap_under_create_rule(value) }
        .downcast::<CFString>()
        .map(|title| title.to_string())
}

#[cfg(target_os = "macos")]
fn ax_window_title(window_ref: *const std::ffi::c_void) -> Option<String> {
    if window_ref.is_null() {
        return None;
    }
    let title_attr = CFString::new("AXTitle");
    let mut title_value: CFTypeRef = std::ptr::null();
    let status = unsafe {
        AXUIElementCopyAttributeValue(
            window_ref,
            title_attr.as_concrete_TypeRef() as *const std::ffi::c_void,
            &mut title_value,
        )
    };
    if status != 0 || title_value.is_null() {
        return None;
    }
    let title = unsafe { CFType::wrap_under_create_rule(title_value) }
        .downcast::<CFString>()
        .map(|s| s.to_string())?;
    Some(title)
}

#[cfg(target_os = "macos")]
fn ax_front_window_hint(pid: i32) -> Option<(CGWindowID, String)> {
    let app_ref = unsafe { AXUIElementCreateApplication(pid) };
    if app_ref.is_null() {
        return None;
    }
    let app = unsafe { CFType::wrap_under_create_rule(app_ref as CFTypeRef) };
    let mut windows_value: CFTypeRef = std::ptr::null();
    let windows_attr = CFString::new("AXWindows");
    let windows_status = unsafe {
        AXUIElementCopyAttributeValue(
            app.as_CFTypeRef() as *const c_void,
            windows_attr.as_concrete_TypeRef() as *const c_void,
            &mut windows_value,
        )
    };
    if windows_status != 0 || windows_value.is_null() {
        return None;
    }
    let windows: CFArray<*const c_void> =
        unsafe { CFArray::wrap_under_create_rule(windows_value as CFArrayRef) };
    let first = windows.get(0)?;
    if first.is_null() {
        return None;
    }
    let mut window_id = 0;
    let id_status = unsafe { _AXUIElementGetWindow(*first, &mut window_id) };
    if id_status != 0 || window_id == 0 {
        return None;
    }
    let title = ax_window_title(*first)
        .unwrap_or_default()
        .to_ascii_lowercase();
    Some((window_id, title))
}

#[cfg(target_os = "macos")]
fn ax_consider_window_for_project(
    window_ref: *const c_void,
    sample_source: &str,
    pid: i32,
    project_name: &str,
    hints: &[String],
    seen_window_ids: &mut HashSet<CGWindowID>,
    scanned: &mut usize,
    sample_titles: &mut Vec<String>,
    exact: &mut Option<WindowMatch>,
    exact_priority: &mut i32,
    hint_match: &mut Option<WindowMatch>,
) {
    if window_ref.is_null() {
        return;
    }
    let mut window_id = 0;
    let id_status = unsafe { _AXUIElementGetWindow(window_ref, &mut window_id) };
    if id_status != 0 || window_id == 0 {
        return;
    }
    if !seen_window_ids.insert(window_id) {
        return;
    }

    *scanned += 1;
    let title = ax_window_title(window_ref)
        .unwrap_or_default()
        .to_ascii_lowercase();
    if sample_titles.len() < 8 {
        sample_titles.push(format!("{}:{}", sample_source, shorten_for_log(&title, 80)));
    }

    if let Some(priority) = project_match_priority(&title, project_name) {
        if priority > *exact_priority {
            *exact_priority = priority;
            *exact = Some(WindowMatch {
                pid,
                window_id,
                title: title.clone(),
                match_kind: "ax-project-name",
                is_on_screen: true,
            });
        }
    }

    if hint_match.is_none()
        && !hints.is_empty()
        && hints
            .iter()
            .any(|hint| !hint.is_empty() && title.contains(hint))
    {
        *hint_match = Some(WindowMatch {
            pid,
            window_id,
            title: title.clone(),
            match_kind: "ax-hint",
            is_on_screen: true,
        });
    }
}

#[cfg(target_os = "macos")]
fn ax_find_window_for_project(
    attempt_id: u64,
    pid: i32,
    project_name: &str,
    hints: &[String],
) -> Option<WindowMatch> {
    let app_ref = unsafe { AXUIElementCreateApplication(pid) };
    if app_ref.is_null() {
        log::warn!(
            target: "editor.switch",
            "[{}] ax-match create-application failed pid={}",
            attempt_id,
            pid
        );
        return None;
    }
    let app = unsafe { CFType::wrap_under_create_rule(app_ref as CFTypeRef) };
    let mut exact: Option<WindowMatch> = None;
    let mut exact_priority = -1;
    let mut hint_match: Option<WindowMatch> = None;
    let mut scanned = 0usize;
    let mut sample_titles: Vec<String> = Vec::new();
    let mut seen_window_ids: HashSet<CGWindowID> = HashSet::new();

    let mut windows_value: CFTypeRef = std::ptr::null();
    let windows_attr = CFString::new("AXWindows");
    let windows_status = unsafe {
        AXUIElementCopyAttributeValue(
            app.as_CFTypeRef() as *const c_void,
            windows_attr.as_concrete_TypeRef() as *const c_void,
            &mut windows_value,
        )
    };
    if windows_status == 0 && !windows_value.is_null() {
        let windows: CFArray<*const c_void> =
            unsafe { CFArray::wrap_under_create_rule(windows_value as CFArrayRef) };
        for item in windows.iter() {
            ax_consider_window_for_project(
                *item,
                "ax",
                pid,
                project_name,
                hints,
                &mut seen_window_ids,
                &mut scanned,
                &mut sample_titles,
                &mut exact,
                &mut exact_priority,
                &mut hint_match,
            );
        }
    } else {
        log::warn!(
            target: "editor.switch",
            "[{}] ax-match fetch-windows failed pid={} status={} has_value={}",
            attempt_id,
            pid,
            windows_status,
            !windows_value.is_null()
        );
    }

    // Brute-force AX window discovery, similar to DockDoor, to include windows not returned by AXWindows.
    if exact.is_none() && hint_match.is_none() {
        let mut token = [0u8; 20];
        token[0..4].copy_from_slice(&pid.to_ne_bytes());
        token[4..8].copy_from_slice(&0i32.to_ne_bytes());
        token[8..12].copy_from_slice(&0x636F_636Fi32.to_ne_bytes());
        for ax_id in 0u64..1000 {
            token[12..20].copy_from_slice(&ax_id.to_ne_bytes());
            let token_data = CFData::from_buffer(&token);
            let window_ref = unsafe {
                _AXUIElementCreateWithRemoteToken(token_data.as_CFTypeRef() as *const c_void)
            };
            if window_ref.is_null() {
                continue;
            }
            let element = unsafe { CFType::wrap_under_create_rule(window_ref as CFTypeRef) };
            ax_consider_window_for_project(
                element.as_CFTypeRef() as *const c_void,
                "brute",
                pid,
                project_name,
                hints,
                &mut seen_window_ids,
                &mut scanned,
                &mut sample_titles,
                &mut exact,
                &mut exact_priority,
                &mut hint_match,
            );
            if exact.is_some() {
                break;
            }
        }
    }

    let selected = exact.or(hint_match);
    match &selected {
        Some(m) => log::info!(
            target: "editor.switch",
            "[{}] ax-match selected kind={} pid={} wid={} title='{}' scanned={}",
            attempt_id,
            m.match_kind,
            m.pid,
            m.window_id,
            shorten_for_log(&m.title, 120),
            scanned
        ),
        None => log::warn!(
            target: "editor.switch",
            "[{}] ax-match no-match pid={} project='{}' scanned={} sample_titles={:?}",
            attempt_id,
            pid,
            project_name,
            scanned,
            sample_titles
        ),
    }

    selected
}

#[cfg(target_os = "macos")]
fn find_vscode_window_for_project(
    attempt_id: u64,
    path: &str,
    project_name: Option<&str>,
) -> Option<WindowMatch> {
    let start = Instant::now();
    let options = window::kCGWindowListOptionAll | window::kCGWindowListExcludeDesktopElements;
    let windows = window::copy_window_info(options, kCGNullWindowID)?;
    let hints = make_project_hints(path, project_name);
    let normalized_project_name = project_name
        .map(|name| name.trim().to_ascii_lowercase())
        .filter(|name| !name.is_empty());

    let key_window_number = unsafe { CFString::wrap_under_get_rule(window::kCGWindowNumber) };
    let key_window_pid = unsafe { CFString::wrap_under_get_rule(window::kCGWindowOwnerPID) };
    let key_window_owner = unsafe { CFString::wrap_under_get_rule(window::kCGWindowOwnerName) };
    let key_window_name = unsafe { CFString::wrap_under_get_rule(window::kCGWindowName) };
    let key_window_layer = unsafe { CFString::wrap_under_get_rule(window::kCGWindowLayer) };
    let key_window_onscreen = unsafe { CFString::wrap_under_get_rule(window::kCGWindowIsOnscreen) };

    let mut exact_project_match: Option<WindowMatch> = None;
    let mut exact_project_priority = -1;
    let mut hinted_match: Option<WindowMatch> = None;
    let mut fallback: Option<WindowMatch> = None;
    let mut fallback_candidates: Vec<WindowMatch> = Vec::new();
    let mut scanned = 0usize;
    let mut vscode_candidates = 0usize;
    let mut sample_titles: Vec<String> = Vec::new();
    let mut candidate_pids: Vec<i32> = Vec::new();

    for item in windows.iter() {
        scanned += 1;
        let dict_ref = *item as CFDictionaryRef;
        if dict_ref.is_null() {
            continue;
        }
        let dict: CFDictionary<CFString, CFType> =
            unsafe { CFDictionary::wrap_under_get_rule(dict_ref) };

        let owner_name = dict_string(&dict, &key_window_owner).unwrap_or_default();
        if !is_vscode_owner(&owner_name) {
            continue;
        }
        vscode_candidates += 1;

        let layer = dict_i64(&dict, &key_window_layer).unwrap_or(-1);
        if layer != 0 {
            continue;
        }

        let pid = match dict_i64(&dict, &key_window_pid) {
            Some(value) if value > 0 => value as i32,
            _ => continue,
        };
        if !candidate_pids.contains(&pid) {
            candidate_pids.push(pid);
        }
        let window_id = match dict_i64(&dict, &key_window_number) {
            Some(value) if value > 0 => value as CGWindowID,
            _ => continue,
        };
        let is_on_screen = dict_bool(&dict, &key_window_onscreen).unwrap_or(false);

        let mut title = dict_string(&dict, &key_window_name).unwrap_or_default();
        if title.trim().is_empty() {
            if let Some(cgs_title) = cgs_window_title(window_id) {
                title = cgs_title;
            }
        }
        let title = title.to_ascii_lowercase();
        if sample_titles.len() < 8 {
            sample_titles.push(shorten_for_log(&title, 80));
        }

        if let Some(project_name) = normalized_project_name.as_ref() {
            if let Some(priority) = project_match_priority(&title, project_name) {
                let should_replace = priority > exact_project_priority
                    || (priority == exact_project_priority
                        && is_on_screen
                        && exact_project_match
                            .as_ref()
                            .is_some_and(|existing| !existing.is_on_screen));
                if should_replace {
                    exact_project_priority = priority;
                    exact_project_match = Some(WindowMatch {
                        pid,
                        window_id,
                        title: title.clone(),
                        match_kind: "project-name",
                        is_on_screen,
                    });
                }
            }
        }

        if hinted_match.is_none()
            && !hints.is_empty()
            && hints.iter().any(|hint| title.contains(hint))
        {
            hinted_match = Some(WindowMatch {
                pid,
                window_id,
                title: title.clone(),
                match_kind: "hint",
                is_on_screen,
            });
        } else if hinted_match
            .as_ref()
            .is_some_and(|existing| !existing.is_on_screen && is_on_screen)
            && !hints.is_empty()
            && hints.iter().any(|hint| title.contains(hint))
        {
            hinted_match = Some(WindowMatch {
                pid,
                window_id,
                title: title.clone(),
                match_kind: "hint",
                is_on_screen,
            });
        }
        if fallback.is_none()
            || fallback
                .as_ref()
                .is_some_and(|existing| !existing.is_on_screen && is_on_screen)
        {
            fallback = Some(WindowMatch {
                pid,
                window_id,
                title: title.clone(),
                match_kind: "fallback-first-vscode",
                is_on_screen,
            });
        }
        fallback_candidates.push(WindowMatch {
            pid,
            window_id,
            title: title.clone(),
            match_kind: "fallback-candidate",
            is_on_screen,
        });
    }

    let mut ax_match: Option<WindowMatch> = None;
    if exact_project_match.is_none()
        && normalized_project_name.is_some()
        && !candidate_pids.is_empty()
    {
        if let Some(project_name) = normalized_project_name.as_ref() {
            for pid in candidate_pids {
                if let Some(m) = ax_find_window_for_project(attempt_id, pid, project_name, &hints) {
                    ax_match = Some(m);
                    break;
                }
            }
        }
    }

    let mut selected = exact_project_match
        .or(ax_match)
        .or(hinted_match)
        .or(fallback);

    // If we only have fallback and AX reports a front window with a different title,
    // avoid picking that same front window ID so project-switch still has a chance.
    if let (Some(project_name), Some(current_selected)) =
        (normalized_project_name.as_ref(), selected.as_ref())
    {
        if current_selected.match_kind == "fallback-first-vscode" {
            if let Some((ax_front_id, ax_front_title)) = ax_front_window_hint(current_selected.pid)
            {
                let front_matches_requested =
                    project_match_priority(&ax_front_title, project_name).is_some();
                if !front_matches_requested && current_selected.window_id == ax_front_id {
                    let alternate = fallback_candidates
                        .iter()
                        .find(|candidate| {
                            candidate.pid == current_selected.pid
                                && candidate.window_id != ax_front_id
                                && candidate.is_on_screen
                        })
                        .or_else(|| {
                            fallback_candidates.iter().find(|candidate| {
                                candidate.pid == current_selected.pid
                                    && candidate.window_id != ax_front_id
                            })
                        });
                    if let Some(alternate) = alternate {
                        log::info!(
                            target: "editor.switch",
                            "[{}] fallback-adjust using non-front window pid={} front_wid={} front_title='{}' alt_wid={} alt_onscreen={} candidates={}",
                            attempt_id,
                            current_selected.pid,
                            ax_front_id,
                            shorten_for_log(&ax_front_title, 120),
                            alternate.window_id,
                            alternate.is_on_screen,
                            fallback_candidates.len()
                        );
                        selected = Some(WindowMatch {
                            pid: alternate.pid,
                            window_id: alternate.window_id,
                            title: alternate.title.clone(),
                            match_kind: "fallback-non-front-vscode",
                            is_on_screen: alternate.is_on_screen,
                        });
                    } else {
                        log::warn!(
                            target: "editor.switch",
                            "[{}] fallback-adjust no-alternate pid={} front_wid={} candidates={}",
                            attempt_id,
                            current_selected.pid,
                            ax_front_id,
                            fallback_candidates.len()
                        );
                    }
                }
            }
        }
    }
    match &selected {
        Some(m) => {
            log::info!(
                target: "editor.switch",
                "[{}] window-scan selected kind={} pid={} wid={} title='{}' onscreen={} scanned={} vscode_candidates={} elapsed_ms={}",
                attempt_id,
                m.match_kind,
                m.pid,
                m.window_id,
                shorten_for_log(&m.title, 120),
                m.is_on_screen,
                scanned,
                vscode_candidates,
                start.elapsed().as_millis()
            );
        }
        None => {
            log::warn!(
                target: "editor.switch",
                "[{}] window-scan no-match scanned={} vscode_candidates={} hints={:?} sample_titles={:?} elapsed_ms={}",
                attempt_id,
                scanned,
                vscode_candidates,
                hints,
                sample_titles,
                start.elapsed().as_millis()
            );
        }
    }

    selected
}

#[cfg(target_os = "macos")]
fn dockdoor_make_key_window(
    attempt_id: u64,
    post_event_record: SLPSPostEventRecordTo,
    psn: &mut ProcessSerialNumber,
    window_id: CGWindowID,
) {
    let mut bytes = [0u8; 0xF8];
    bytes[0x04] = 0xF8;
    bytes[0x3A] = 0x10;
    bytes[0x3C..0x40].copy_from_slice(&window_id.to_le_bytes());
    bytes[0x20..0x30].fill(0xFF);
    bytes[0x08] = 0x01;
    let status1 = unsafe { post_event_record(psn, bytes.as_mut_ptr()) };
    bytes[0x08] = 0x02;
    let status2 = unsafe { post_event_record(psn, bytes.as_mut_ptr()) };
    if status1 != 0 || status2 != 0 {
        log::warn!(
            target: "editor.switch",
            "[{}] make-key-window failed statuses=({}, {}) wid={}",
            attempt_id,
            status1,
            status2,
            window_id
        );
        return;
    }
    log::debug!(
        target: "editor.switch",
        "[{}] make-key-window success wid={}",
        attempt_id,
        window_id
    );
}

#[cfg(target_os = "macos")]
fn ax_raise_window_best_effort(attempt_id: u64, pid: i32, target_window_id: CGWindowID) {
    let app_ref = unsafe { AXUIElementCreateApplication(pid) };
    if app_ref.is_null() {
        log::warn!(
            target: "editor.switch",
            "[{}] ax-raise create-application failed pid={}",
            attempt_id,
            pid
        );
        return;
    }
    let app = unsafe { CFType::wrap_under_create_rule(app_ref as CFTypeRef) };

    let mut windows_value: CFTypeRef = std::ptr::null();
    let windows_attr = CFString::new("AXWindows");
    let windows_status = unsafe {
        AXUIElementCopyAttributeValue(
            app.as_CFTypeRef() as *const std::ffi::c_void,
            windows_attr.as_concrete_TypeRef() as *const std::ffi::c_void,
            &mut windows_value,
        )
    };
    if windows_status != 0 || windows_value.is_null() {
        log::warn!(
            target: "editor.switch",
            "[{}] ax-raise fetch-windows failed pid={} status={} has_value={}",
            attempt_id,
            pid,
            windows_status,
            !windows_value.is_null()
        );
        return;
    }

    let windows: CFArray<*const std::ffi::c_void> =
        unsafe { CFArray::wrap_under_create_rule(windows_value as CFArrayRef) };
    let raise_action = CFString::new("AXRaise");
    let main_attr = CFString::new("AXMain");
    let true_value = CFBoolean::true_value();
    let mut scanned = 0usize;
    let mut matched = false;

    for item in windows.iter() {
        scanned += 1;
        let window_ref = *item;
        if window_ref.is_null() {
            continue;
        }
        let mut window_id = 0;
        let id_status = unsafe { _AXUIElementGetWindow(window_ref, &mut window_id) };
        if id_status != 0 || window_id != target_window_id {
            continue;
        }

        matched = true;
        let raise_status = unsafe {
            AXUIElementPerformAction(
                window_ref,
                raise_action.as_concrete_TypeRef() as *const std::ffi::c_void,
            )
        };
        let main_status = unsafe {
            AXUIElementSetAttributeValue(
                window_ref,
                main_attr.as_concrete_TypeRef() as *const std::ffi::c_void,
                true_value.as_CFTypeRef(),
            )
        };
        log::info!(
            target: "editor.switch",
            "[{}] ax-raise result pid={} wid={} raise_status={} main_status={} scanned={}",
            attempt_id,
            pid,
            target_window_id,
            raise_status,
            main_status,
            scanned
        );
        break;
    }

    if !matched {
        log::warn!(
            target: "editor.switch",
            "[{}] ax-raise no-matching-window pid={} wid={} scanned={}",
            attempt_id,
            pid,
            target_window_id,
            scanned
        );
    }
}

#[cfg(target_os = "macos")]
fn frontmost_window_owner_pid() -> Option<i32> {
    let options =
        window::kCGWindowListOptionOnScreenOnly | window::kCGWindowListExcludeDesktopElements;
    let windows = window::copy_window_info(options, kCGNullWindowID)?;
    let first = windows.get(0)?;
    let dict_ref = *first as CFDictionaryRef;
    if dict_ref.is_null() {
        return None;
    }
    let dict: CFDictionary<CFString, CFType> =
        unsafe { CFDictionary::wrap_under_get_rule(dict_ref) };
    let key_window_pid = unsafe { CFString::wrap_under_get_rule(window::kCGWindowOwnerPID) };
    dict_i64(&dict, &key_window_pid).map(|pid| pid as i32)
}

#[cfg(target_os = "macos")]
fn dockdoor_focus_window(attempt_id: u64, pid: i32, window_id: CGWindowID) -> Result<(), String> {
    let start = Instant::now();
    let api = SKYLIGHT_API
        .as_ref()
        .ok_or_else(|| "Failed to load SkyLight private APIs".to_string())?;

    let mut psn = ProcessSerialNumber {
        high_long_of_psn: 0,
        low_long_of_psn: 0,
    };
    let status = unsafe { GetProcessForPID(pid, &mut psn) };
    if status != 0 {
        log::warn!(
            target: "editor.switch",
            "[{}] GetProcessForPID failed pid={} status={}",
            attempt_id,
            pid,
            status
        );
        return Err(format!("GetProcessForPID failed with status {}", status));
    }

    // Same mode DockDoor uses (`SLPSMode.userGenerated`).
    let user_generated_mode = 0x200u32;
    let max_retries = 3;
    for retry_idx in 0..max_retries {
        let status = unsafe { (api.set_front_process)(&mut psn, window_id, user_generated_mode) };
        if status != 0 {
            log::warn!(
                target: "editor.switch",
                "[{}] _SLPSSetFrontProcessWithOptions failed pid={} wid={} status={} retry={}/{}",
                attempt_id,
                pid,
                window_id,
                status,
                retry_idx + 1,
                max_retries
            );
            if retry_idx + 1 == max_retries {
                return Err(format!(
                    "_SLPSSetFrontProcessWithOptions failed with status {}",
                    status
                ));
            }
            std::thread::sleep(Duration::from_millis(50));
            continue;
        }

        // Keep behavior aligned with DockDoor: attempt key-window promotion but do not fail the switch
        // if SLPSPostEventRecordTo is rejected on this macOS build.
        dockdoor_make_key_window(attempt_id, api.post_event_record, &mut psn, window_id);
        // Same as DockDoor fallback: raise and main the exact AX window corresponding to the target CGWindowID.
        ax_raise_window_best_effort(attempt_id, pid, window_id);
        // Re-assert target focus once more; this helps when make-key and AX are unavailable.
        let reaffirm_status =
            unsafe { (api.set_front_process)(&mut psn, window_id, user_generated_mode) };
        if reaffirm_status != 0 {
            log::warn!(
                target: "editor.switch",
                "[{}] _SLPSSetFrontProcessWithOptions reaffirm failed pid={} wid={} status={} retry={}/{}",
                attempt_id,
                pid,
                window_id,
                reaffirm_status,
                retry_idx + 1,
                max_retries
            );
        }

        let front_pid = frontmost_window_owner_pid();
        if front_pid == Some(pid) {
            log::info!(
                target: "editor.switch",
                "[{}] dockdoor-focus success pid={} wid={} retries={} elapsed_ms={}",
                attempt_id,
                pid,
                window_id,
                retry_idx + 1,
                start.elapsed().as_millis()
            );
            return Ok(());
        }

        log::warn!(
            target: "editor.switch",
            "[{}] dockdoor-focus verify-failed target_pid={} observed_front_pid={:?} retry={}/{}",
            attempt_id,
            pid,
            front_pid,
            retry_idx + 1,
            max_retries
        );
        if retry_idx + 1 < max_retries {
            std::thread::sleep(Duration::from_millis(50));
        }
    }

    // Foreground verification can be unreliable in some macOS states (e.g. transient system windows).
    // Keep DockDoor-style focus attempts, but do not force a CLI fallback that causes dock icon flash.
    log::warn!(
        target: "editor.switch",
        "[{}] dockdoor-focus verify-unconfirmed pid={} wid={} retries={} elapsed_ms={}",
        attempt_id,
        pid,
        window_id,
        max_retries,
        start.elapsed().as_millis()
    );
    Ok(())
}

#[cfg(target_os = "macos")]
fn open_vscode_session_experimental(
    attempt_id: u64,
    path: &str,
    project_name: Option<&str>,
) -> Result<(), String> {
    let start = Instant::now();
    log::info!(
        target: "editor.switch",
        "[{}] experimental-start path='{}' project_name={:?}",
        attempt_id,
        shorten_for_log(path, 160),
        project_name
    );

    if let Some(window_match) = find_vscode_window_for_project(attempt_id, path, project_name) {
        log::info!(
            target: "editor.switch",
            "[{}] experimental-target kind={} pid={} wid={} title='{}'",
            attempt_id,
            window_match.match_kind,
            window_match.pid,
            window_match.window_id,
            shorten_for_log(&window_match.title, 120)
        );
        dockdoor_focus_window(attempt_id, window_match.pid, window_match.window_id)?;
        log::info!(
            target: "editor.switch",
            "[{}] experimental-complete mode=switch elapsed_ms={}",
            attempt_id,
            start.elapsed().as_millis()
        );
        return Ok(());
    }

    // No VS Code window was found to switch to, so open the project normally.
    let child = Command::new("open")
        .args(["-b", "com.microsoft.VSCode", path])
        .spawn()
        .map_err(|e| format!("Failed to open VS Code via experimental flow: {}", e))?;
    log::warn!(
        target: "editor.switch",
        "[{}] experimental-fallback-open pid={} elapsed_ms={}",
        attempt_id,
        child.id(),
        start.elapsed().as_millis()
    );
    Ok(())
}

/// Open a project path in an editor
#[tauri::command]
pub fn open_in_editor(
    path: String,
    editor: String,
    experimental_vs_code_session_opening: Option<bool>,
    project_name: Option<String>,
) -> Result<(), String> {
    let attempt_id = SWITCH_ATTEMPT_COUNTER.fetch_add(1, Ordering::Relaxed);
    let start = Instant::now();
    log::info!(
        target: "editor.switch",
        "[{}] open-in-editor editor={} experimental={} path='{}' project_name={:?}",
        attempt_id,
        editor,
        experimental_vs_code_session_opening.unwrap_or(false),
        shorten_for_log(&path, 160),
        project_name
    );

    #[cfg(target_os = "macos")]
    {
        let use_experimental = experimental_vs_code_session_opening.unwrap_or(false);
        if editor == "code" && use_experimental {
            if let Err(error) =
                open_vscode_session_experimental(attempt_id, &path, project_name.as_deref())
            {
                log::warn!(
                    target: "editor.switch",
                    "[{}] experimental-failed error='{}' falling-back=cli elapsed_ms={}",
                    attempt_id,
                    error,
                    start.elapsed().as_millis()
                );
            } else {
                log::info!(
                    target: "editor.switch",
                    "[{}] open-in-editor complete mode=experimental elapsed_ms={}",
                    attempt_id,
                    start.elapsed().as_millis()
                );
                return Ok(());
            }
        }
    };

    #[cfg(not(target_os = "macos"))]
    let _ = (experimental_vs_code_session_opening, project_name);

    // Map known editor names to their CLI commands, or use the editor string directly for custom commands
    let cmd = match editor.as_str() {
        "zed" => "zed",
        "code" => "code",
        "cursor" => "cursor",
        "sublime" => "subl",
        "neovim" => "nvim",
        "webstorm" => "webstorm",
        "idea" => "idea",
        custom => custom, // Use the provided string directly for custom editors
    };

    let child = Command::new(cmd)
        .arg(&path)
        .env("PATH", enriched_path())
        .spawn()
        .map_err(|e| format!("Failed to open {} in {}: {}", path, editor, e))?;

    log::info!(
        target: "editor.switch",
        "[{}] open-in-editor complete mode=cli cmd={} child_pid={} elapsed_ms={}",
        attempt_id,
        cmd,
        child.id(),
        start.elapsed().as_millis()
    );

    Ok(())
}

/// Open a project path in a terminal
#[tauri::command]
pub fn open_in_terminal(path: String, terminal: String) -> Result<(), String> {
    match terminal.as_str() {
        "ghostty" => {
            Command::new("open")
                .args(["-a", "Ghostty", &path])
                .spawn()
                .map_err(|e| format!("Failed to open Ghostty: {}", e))?;
        }
        "iterm" => {
            // iTerm2 uses AppleScript to open in a specific directory
            let script = format!(
                r#"tell application "iTerm"
                    activate
                    create window with default profile
                    tell current session of current window
                        write text "cd '{}'"
                    end tell
                end tell"#,
                path.replace("'", "'\\''")
            );
            Command::new("osascript")
                .args(["-e", &script])
                .spawn()
                .map_err(|e| format!("Failed to open iTerm2: {}", e))?;
        }
        "kitty" => {
            Command::new("kitty")
                .args(["--directory", &path])
                .env("PATH", enriched_path())
                .spawn()
                .map_err(|e| format!("Failed to open Kitty: {}", e))?;
        }
        "terminal" => {
            // macOS Terminal.app
            let script = format!(
                r#"tell application "Terminal"
                    activate
                    do script "cd '{}'"
                end tell"#,
                path.replace("'", "'\\''")
            );
            Command::new("osascript")
                .args(["-e", &script])
                .spawn()
                .map_err(|e| format!("Failed to open Terminal: {}", e))?;
        }
        "warp" => {
            Command::new("open")
                .args(["-a", "Warp", &path])
                .spawn()
                .map_err(|e| format!("Failed to open Warp: {}", e))?;
        }
        "alacritty" => {
            Command::new("alacritty")
                .args(["--working-directory", &path])
                .env("PATH", enriched_path())
                .spawn()
                .map_err(|e| format!("Failed to open Alacritty: {}", e))?;
        }
        "hyper" => {
            Command::new("open")
                .args(["-a", "Hyper", &path])
                .spawn()
                .map_err(|e| format!("Failed to open Hyper: {}", e))?;
        }
        custom => {
            // Try to open as a macOS app first, then fall back to command with path argument
            let app_result = Command::new("open").args(["-a", custom, &path]).spawn();

            if app_result.is_err() {
                // Fall back to running the command directly with path as argument
                Command::new(custom)
                    .arg(&path)
                    .env("PATH", enriched_path())
                    .spawn()
                    .map_err(|e| format!("Failed to open {}: {}", custom, e))?;
            }
        }
    }

    Ok(())
}

fn escape_shell_single_quoted(value: &str) -> String {
    value.replace('\'', "'\\''")
}

fn escape_applescript_string(value: &str) -> String {
    value.replace('\\', "\\\\").replace('"', "\\\"")
}

fn run_in_terminal_app(path: &str, command: &str) -> Result<(), String> {
    let shell_line = format!(
        "cd '{}' && {}",
        escape_shell_single_quoted(path),
        command.trim()
    );
    let script = format!(
        r#"tell application "Terminal"
            activate
            do script "{}"
        end tell"#,
        escape_applescript_string(&shell_line)
    );

    Command::new("osascript")
        .args(["-e", &script])
        .spawn()
        .map_err(|e| format!("Failed to run command in Terminal: {}", e))?;

    Ok(())
}

fn run_in_iterm(path: &str, command: &str) -> Result<(), String> {
    let shell_line = format!(
        "cd '{}' && {}",
        escape_shell_single_quoted(path),
        command.trim()
    );
    let script = format!(
        r#"tell application "iTerm"
            activate
            create window with default profile
            tell current session of current window
                write text "{}"
            end tell
        end tell"#,
        escape_applescript_string(&shell_line)
    );

    Command::new("osascript")
        .args(["-e", &script])
        .spawn()
        .map_err(|e| format!("Failed to run command in iTerm2: {}", e))?;

    Ok(())
}

/// Run an arbitrary command in a project's directory
#[tauri::command]
pub fn run_project_command(path: String, command: String, terminal: String) -> Result<(), String> {
    let trimmed_command = command.trim();
    if trimmed_command.is_empty() {
        return Err("Command cannot be empty".to_string());
    }

    #[cfg(target_os = "macos")]
    {
        match terminal.as_str() {
            "iterm" => run_in_iterm(&path, trimmed_command),
            "terminal" => run_in_terminal_app(&path, trimmed_command),
            "kitty" => {
                Command::new("kitty")
                    .args(["--directory", &path, "/bin/zsh", "-lc", trimmed_command])
                    .env("PATH", enriched_path())
                    .spawn()
                    .map_err(|e| format!("Failed to run command in Kitty: {}", e))?;
                Ok(())
            }
            "alacritty" => {
                Command::new("alacritty")
                    .args([
                        "--working-directory",
                        &path,
                        "-e",
                        "/bin/zsh",
                        "-lc",
                        trimmed_command,
                    ])
                    .env("PATH", enriched_path())
                    .spawn()
                    .map_err(|e| format!("Failed to run command in Alacritty: {}", e))?;
                Ok(())
            }
            "ghostty" => {
                let run_result = Command::new("ghostty")
                    .args([
                        "--working-directory",
                        &path,
                        "-e",
                        "/bin/zsh",
                        "-lc",
                        trimmed_command,
                    ])
                    .env("PATH", enriched_path())
                    .spawn();
                if run_result.is_err() {
                    return run_in_terminal_app(&path, trimmed_command);
                }
                Ok(())
            }
            // Warp/Hyper/custom app targets don't have a stable CLI contract for sending a command,
            // so we fall back to Terminal.app to ensure output is visible and interruptible.
            _ => run_in_terminal_app(&path, trimmed_command),
        }
    }

    #[cfg(not(target_os = "macos"))]
    let _ = terminal;

    #[cfg(not(target_os = "macos"))]
    let mut process = {
        let mut cmd = Command::new("/bin/zsh");
        cmd.args(["-lc", trimmed_command]);
        cmd
    };

    #[cfg(not(target_os = "macos"))]
    process.current_dir(&path).env("PATH", enriched_path());
    #[cfg(not(target_os = "macos"))]
    process
        .spawn()
        .map_err(|e| format!("Failed to run command in {}: {}", path, e))?;

    #[cfg(not(target_os = "macos"))]
    Ok(())
}
