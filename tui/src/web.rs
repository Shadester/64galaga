//! The browser front end: plain `extern "C"` functions for a small JavaScript page (docs/tui/index.html), built with tools/build_web.sh as a
//! WebAssembly module with no imports. The page calls `web_tick` every 20 ms with the keys, then `web_draw`, and draws the cells it gets.
//! The functions are ordinary Rust, so the tests call them natively.
use crate::game::*;
use crate::render::*;
use std::cell::RefCell;

/// Keys for `web_tick`: held keys, and one-tick pulses (a key press) for fire, pause and quit.
pub const K_LEFT: u32 = 1;
pub const K_RIGHT: u32 = 2;
pub const K_FIRE: u32 = 4;
pub const K_PAUSE: u32 = 8;
pub const K_QUIT: u32 = 16;
/// Flags from `web_tick`
pub const F_SAVE: u32 = 1; // the hi-score changed or the game ended: the page saves `web_hi()`
pub const F_EXIT: u32 = 2; // Q on the title screen

struct Web {
    game: Game,
    renderer: Option<Renderer>,
    cols: usize,
    rows: usize,
    buf: Vec<u8>,
    start_stage: i32,
    god: bool,
    autoplay: bool,
}

thread_local! {
    static WEB: RefCell<Option<Web>> = const { RefCell::new(None) };
}

fn with<R>(f: impl FnOnce(&mut Web) -> R) -> Option<R> {
    WEB.with(|w| w.borrow_mut().as_mut().map(f))
}

/// Start (again): the hi-score from the page, the options (`start_stage` 0 = stage 1), and the size of the window in cells.
#[no_mangle]
pub extern "C" fn web_init(hi: i32, start_stage: i32, god: i32, autoplay: i32, cols: u32, rows: u32) {
    let (cols, rows) = (cols as usize, rows as usize);
    let w = Web {
        game: Game::new(hi),
        renderer: layout(cols, rows).map(Renderer::new),
        cols,
        rows,
        buf: Vec::new(),
        start_stage,
        god: god != 0,
        autoplay: autoplay != 0,
    };
    WEB.with(|x| *x.borrow_mut() = Some(w));
}

/// The window changed its size.
#[no_mangle]
pub extern "C" fn web_resize(cols: u32, rows: u32) {
    with(|w| {
        w.cols = cols as usize;
        w.rows = rows as usize;
        w.renderer = layout(w.cols, w.rows).map(Renderer::new);
    });
}

/// One tick of the game (50 a second) with the keys (K_*). Returns F_* flags.
#[no_mangle]
pub extern "C" fn web_tick(keys: u32) -> u32 {
    with(|w| {
        let typed = Input { left: keys & K_LEFT != 0, right: keys & K_RIGHT != 0, fire: keys & K_FIRE != 0, pause: keys & K_PAUSE != 0, quit: keys & K_QUIT != 0 };
        let mut flags = 0;
        if w.game.state == S_TITLE && typed.quit {
            flags |= F_EXIT;
        }
        let inp = if w.autoplay { Input { pause: typed.pause, quit: typed.quit, ..game_autoplay(&w.game) } } else { typed };
        if w.god {
            w.game.invuln = 100;
        }
        w.game.tick(&inp, w.start_stage);
        if w.game.save_req != 0 {
            flags |= F_SAVE;
        }
        w.game.snd = 0;
        w.game.save_req = 0;
        flags
    })
    .unwrap_or(0)
}

/// Draw the window into the cell buffer and return its address (12 bytes a cell, row by row: the character as a u32, fg r g b, bg r g b, 2 spare).
/// The address is good until the next call.
#[no_mangle]
pub extern "C" fn web_draw() -> *const u8 {
    with(|w| {
        let f = match w.renderer.as_mut() {
            Some(r) => r.draw(&w.game, w.cols, w.rows),
            None => too_small(w.cols, w.rows),
        };
        w.buf.clear();
        for c in &f.cells {
            w.buf.extend_from_slice(&(c.ch as u32).to_le_bytes());
            w.buf.extend_from_slice(&c.fg);
            w.buf.extend_from_slice(&c.bg);
            w.buf.extend_from_slice(&[0, 0]);
        }
        w.buf.as_ptr()
    })
    .unwrap_or(std::ptr::null())
}

/// The number of cells `web_draw` fills.
#[no_mangle]
pub extern "C" fn web_cells() -> u32 {
    with(|w| (w.cols * w.rows) as u32).unwrap_or(0)
}

#[no_mangle]
pub extern "C" fn web_hi() -> i32 {
    with(|w| w.game.hi).unwrap_or(0)
}

#[no_mangle]
pub extern "C" fn web_state() -> i32 {
    with(|w| w.game.state).unwrap_or(-1)
}

/// A number made of the score, stage, lives, ship position and frame: the tests compare it with another run.
#[no_mangle]
pub extern "C" fn web_checksum() -> i32 {
    with(|w| checksum(&w.game)).unwrap_or(0)
}

pub fn checksum(g: &Game) -> i32 {
    ((g.score as i64 * 31 + g.stage as i64 * 1009 + g.lives as i64 * 13 + g.px as i64 * 3 + g.frame as i64) & 0x7fff_ffff) as i32
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_exports_play_the_same_game() {
        let (cols, rows) = (107u32, 36u32);
        web_init(1234, 0, 1, 1, cols, rows);
        let mut g = Game::new(1234);
        for _ in 0..4000 {
            web_tick(0);
            g.invuln = 100;
            let inp = game_autoplay(&g);
            g.tick(&inp, 0);
            g.snd = 0;
            g.save_req = 0;
        }
        assert_eq!(web_checksum(), checksum(&g));
        assert!(g.score > 0);
        assert_eq!(web_cells(), cols * rows);
        let p = web_draw();
        let cells = unsafe { std::slice::from_raw_parts(p, (cols * rows * 12) as usize) };
        assert!(cells.chunks(12).any(|c| u32::from_le_bytes([c[0], c[1], c[2], c[3]]) == '▀' as u32 && c[4..7] != [0, 0, 0]));
        web_resize(70, 20); // too small: the message
        let p = web_draw();
        let cells = unsafe { std::slice::from_raw_parts(p, 70 * 20 * 12) };
        assert!(cells.chunks(12).any(|c| u32::from_le_bytes([c[0], c[1], c[2], c[3]]) == 'P' as u32));
    }
}
