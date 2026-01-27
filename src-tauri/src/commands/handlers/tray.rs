//! Tray-related command handlers

/// Update the tray icon title with session counts
#[tauri::command]
pub fn update_tray_title(
    app: tauri::AppHandle,
    total: usize,
    waiting: usize,
) -> Result<(), String> {
    let title = if waiting > 0 {
        format!("{} ({} idle)", total, waiting)
    } else if total > 0 {
        format!("{}", total)
    } else {
        String::new()
    };

    if let Some(tray) = app.tray_by_id("main-tray") {
        tray.set_title(Some(&title))
            .map_err(|e| format!("Failed to set tray title: {}", e))?;
    }
    Ok(())
}
