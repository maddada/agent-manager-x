use chrono::Local;
use log::{Level, LevelFilter, Metadata, Record, SetLoggerError};
use std::fs::{File, OpenOptions};
use std::io::Write;
use std::path::PathBuf;
use std::sync::Mutex;

struct FileLogger {
    file: Mutex<Option<File>>,
    log_path: PathBuf,
    switch_file: Mutex<Option<File>>,
    switch_log_path: PathBuf,
}

impl FileLogger {
    fn new() -> Self {
        let log_path = get_log_path();
        let file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&log_path)
            .ok();
        let switch_log_path = get_switch_log_path();
        let switch_file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&switch_log_path)
            .ok();

        FileLogger {
            file: Mutex::new(file),
            log_path,
            switch_file: Mutex::new(switch_file),
            switch_log_path,
        }
    }
}

impl log::Log for FileLogger {
    fn enabled(&self, metadata: &Metadata) -> bool {
        metadata.level() <= Level::Debug
    }

    fn log(&self, record: &Record) {
        if self.enabled(record.metadata()) {
            let timestamp = Local::now().format("%Y-%m-%d %H:%M:%S%.3f");
            let level = record.level();
            let target = record.target();
            let message = record.args();

            let log_line = format!("[{timestamp}] [{level:5}] [{target}] {message}\n");

            // Write to file
            if let Ok(mut guard) = self.file.lock() {
                if let Some(ref mut file) = *guard {
                    let _ = file.write_all(log_line.as_bytes());
                    let _ = file.flush();
                }
            }
            // Mirror only editor-switch logs to a dedicated file.
            if target == "editor.switch" {
                if let Ok(mut guard) = self.switch_file.lock() {
                    if let Some(ref mut file) = *guard {
                        let _ = file.write_all(log_line.as_bytes());
                        let _ = file.flush();
                    }
                }
            }

            // Also print to stderr in dev mode
            #[cfg(debug_assertions)]
            eprint!("{}", log_line);
        }
    }

    fn flush(&self) {
        if let Ok(mut guard) = self.file.lock() {
            if let Some(ref mut file) = *guard {
                let _ = file.flush();
            }
        }
        if let Ok(mut guard) = self.switch_file.lock() {
            if let Some(ref mut file) = *guard {
                let _ = file.flush();
            }
        }
    }
}

fn get_log_path() -> PathBuf {
    let log_dir = get_log_dir();
    log_dir.join("debug.log")
}

fn get_switch_log_path() -> PathBuf {
    let log_dir = get_log_dir();
    log_dir.join("editor-switch.log")
}

fn get_log_dir() -> PathBuf {
    let log_dir = dirs::cache_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join("agent-manager-x");
    let _ = std::fs::create_dir_all(&log_dir);
    log_dir
}

static LOGGER: std::sync::OnceLock<FileLogger> = std::sync::OnceLock::new();

/// Initialize the logger. Only logs in debug builds.
pub fn init() -> Result<(), SetLoggerError> {
    let enabled = cfg!(debug_assertions) || env_logging_enabled();
    if !enabled {
        log::set_max_level(LevelFilter::Off);
        return Ok(());
    }

    let logger = LOGGER.get_or_init(FileLogger::new);

    // Clear the log file on startup
    if let Ok(file) = File::create(&logger.log_path) {
        drop(file);
    }
    if let Ok(file) = File::create(&logger.switch_log_path) {
        drop(file);
    }

    // Reinitialize file handles after clearing
    if let Ok(mut guard) = logger.file.lock() {
        *guard = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&logger.log_path)
            .ok();
    }
    if let Ok(mut guard) = logger.switch_file.lock() {
        *guard = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&logger.switch_log_path)
            .ok();
    }

    log::set_logger(logger)?;
    log::set_max_level(LevelFilter::Debug);

    log::info!("=== Agent Manager X Debug Log Started ===");
    log::info!("Log file: {:?}", logger.log_path);
    log::info!("Switch log file: {:?}", logger.switch_log_path);

    Ok(())
}

fn env_logging_enabled() -> bool {
    std::env::var("AMX_DEBUG_LOG")
        .or_else(|_| std::env::var("AGENT_MANAGER_X_DEBUG_LOG"))
        .map(|value| {
            let trimmed = value.trim();
            !trimmed.is_empty() && trimmed != "0"
        })
        .unwrap_or(false)
}

/// Get the path to the log file
pub fn get_log_file_path() -> PathBuf {
    get_log_path()
}

/// Get the path to the dedicated editor switch log file
pub fn get_switch_log_file_path() -> PathBuf {
    get_switch_log_path()
}
