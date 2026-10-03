//! The hi-score file: ~/.local/share/galaga-tui/hiscore (a number in text).
use std::path::PathBuf;

fn path() -> Option<PathBuf> {
    let home = std::env::var_os("HOME")?;
    Some(PathBuf::from(home).join(".local/share/galaga-tui/hiscore"))
}

pub fn load() -> i32 {
    path().and_then(|p| std::fs::read_to_string(p).ok()).and_then(|s| s.trim().parse().ok()).unwrap_or(0)
}

pub fn save(hi: i32) {
    if let Some(p) = path() {
        if let Some(d) = p.parent() {
            let _ = std::fs::create_dir_all(d);
        }
        let _ = std::fs::write(p, hi.to_string());
    }
}
