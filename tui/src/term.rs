//! The terminal: raw mode, the alternate screen, and writing a `Frame` as the cells that changed since the last one.
use crate::render::{Cell, Frame, Rgb};
use crossterm::event::{KeyboardEnhancementFlags, PopKeyboardEnhancementFlags, PushKeyboardEnhancementFlags};
use crossterm::terminal::{self, EnterAlternateScreen, LeaveAlternateScreen};
use crossterm::{cursor, execute};
use std::fmt::Write as _;
use std::io::{self, Write};
use std::sync::atomic::{AtomicBool, Ordering};

static ACTIVE: AtomicBool = AtomicBool::new(false);

/// Give the terminal back (also from the panic hook): the cursor, the normal screen, the keys.
pub fn restore() {
    if ACTIVE.swap(false, Ordering::SeqCst) {
        let mut out = io::stdout();
        let _ = execute!(out, PopKeyboardEnhancementFlags, cursor::Show, LeaveAlternateScreen);
        let _ = terminal::disable_raw_mode();
    }
}

pub struct Term {
    prev: Option<Frame>,
    pub truecolor: bool,
    pub enhanced: bool,
}

impl Term {
    pub fn new() -> io::Result<Term> {
        terminal::enable_raw_mode()?;
        let mut out = io::stdout();
        execute!(out, EnterAlternateScreen, cursor::Hide)?;
        ACTIVE.store(true, Ordering::SeqCst);
        let enhanced = terminal::supports_keyboard_enhancement().unwrap_or(false);
        if enhanced {
            execute!(out, PushKeyboardEnhancementFlags(KeyboardEnhancementFlags::DISAMBIGUATE_ESCAPE_CODES | KeyboardEnhancementFlags::REPORT_EVENT_TYPES))?;
        }
        let ct = std::env::var("COLORTERM").unwrap_or_default();
        let truecolor = ct.contains("truecolor") || ct.contains("24bit");
        let prev_hook = std::panic::take_hook();
        std::panic::set_hook(Box::new(move |info| {
            restore();
            prev_hook(info);
        }));
        Ok(Term { prev: None, truecolor, enhanced })
    }

    pub fn size(&self) -> (usize, usize) {
        let (c, r) = terminal::size().unwrap_or((80, 24));
        (c as usize, r as usize)
    }

    /// Forget the last frame: the next one is written whole (after a resize, or after a message that covered the screen).
    pub fn invalidate(&mut self) {
        self.prev = None;
        let _ = execute!(io::stdout(), terminal::Clear(terminal::ClearType::All));
    }

    /// Write the cells that differ from the last frame, in one write.
    pub fn present(&mut self, f: Frame) -> io::Result<()> {
        let mut s = String::with_capacity(16 * 1024);
        let full = match &self.prev {
            Some(p) => p.cols != f.cols || p.rows != f.rows,
            None => true,
        };
        let mut cur: Option<(Rgb, Rgb)> = None;
        let mut at: Option<(usize, usize)> = None; // where the cursor is after the last cell
        for y in 0..f.rows {
            for x in 0..f.cols {
                let c = f.cells[y * f.cols + x];
                if !full && self.prev.as_ref().map(|p| p.cells[y * f.cols + x] == c).unwrap_or(false) {
                    continue;
                }
                if at != Some((x, y)) {
                    let _ = write!(s, "\x1b[{};{}H", y + 1, x + 1);
                }
                if cur != Some((c.fg, c.bg)) {
                    self.colors(&mut s, &c);
                    cur = Some((c.fg, c.bg));
                }
                s.push(c.ch);
                at = Some((x + 1, y));
            }
        }
        if !s.is_empty() {
            s.push_str("\x1b[0m");
            let mut out = io::stdout().lock();
            out.write_all(s.as_bytes())?;
            out.flush()?;
        }
        self.prev = Some(f);
        Ok(())
    }

    fn colors(&self, s: &mut String, c: &Cell) {
        if self.truecolor {
            let _ = write!(s, "\x1b[38;2;{};{};{};48;2;{};{};{}m", c.fg[0], c.fg[1], c.fg[2], c.bg[0], c.bg[1], c.bg[2]);
        } else {
            let _ = write!(s, "\x1b[38;5;{};48;5;{}m", nearest_256(c.fg), nearest_256(c.bg));
        }
    }
}

impl Drop for Term {
    fn drop(&mut self) {
        restore();
    }
}

/// The nearest colour of the 256 colour palette: the 6 x 6 x 6 cube or the 24 greys.
pub fn nearest_256(c: Rgb) -> u8 {
    let level = |v: u8| -> u32 { if v < 48 { 0 } else if v < 115 { 1 } else { (v as u32 - 35) / 40 } };
    let (r, g, b) = (level(c[0]), level(c[1]), level(c[2]));
    let cube = |l: u32| -> i32 { if l == 0 { 0 } else { 55 + 40 * l as i32 } };
    let cube_idx = 16 + 36 * r + 6 * g + b;
    let d_cube = (cube(r) - c[0] as i32).pow(2) + (cube(g) - c[1] as i32).pow(2) + (cube(b) - c[2] as i32).pow(2);
    let avg = (c[0] as i32 + c[1] as i32 + c[2] as i32) / 3;
    let gi = ((avg - 8).max(0) / 10).min(23);
    let gv = 8 + 10 * gi;
    let d_grey = (gv - c[0] as i32).pow(2) + (gv - c[1] as i32).pow(2) + (gv - c[2] as i32).pow(2);
    if d_grey < d_cube { (232 + gi) as u8 } else { cube_idx as u8 }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn palette() {
        assert_eq!(nearest_256([0, 0, 0]), 16);
        assert_eq!(nearest_256([255, 255, 255]), 231);
        assert_eq!(nearest_256([255, 0, 0]), 196);
        assert!((232..=255).contains(&nearest_256([128, 128, 128])));
    }
}
