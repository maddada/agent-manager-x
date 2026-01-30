use chrono::Local;
use log::{Level, LevelFilter, Metadata, Record, SetLoggerError};
use std::fs::{File, OpenOptions};
use std::io::Write;
use std::path::PathBuf;
use std::sync::Mutex;

struct FileLogger {
    file: Mutex<Option<File>>,
    log_path: PathBuf,
}

impl FileLogger {
    fn new() -> Self {
        let log_path = get_log_path();
        let file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&log_path)
            .ok();

        FileLogger {
            file: Mutex::new(file),
            log_path,
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
    }
}

fn get_log_path() -> PathBuf {
    let log_dir = dirs::cache_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join("agent-manager-x");

    // Create directory if it doesn't exist
    let _ = std::fs::create_dir_all(&log_dir);

    log_dir.join("debug.log")
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

    // Reinitialize file handle after clearing
    if let Ok(mut guard) = logger.file.lock() {
        *guard = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&logger.log_path)
            .ok();
    }

    log::set_logger(logger)?;
    log::set_max_level(LevelFilter::Debug);

    log::info!("=== Agent Manager X Debug Log Started ===");
    log::info!("Log file: {:?}", logger.log_path);

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
