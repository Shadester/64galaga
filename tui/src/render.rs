//! Drawing: the game state becomes a grid of terminal cells. The play area is a canvas of pixels (320 x 200 game pixels divided by the
//! scale k), two canvas pixels in one cell: the half block "▀" has the upper pixel as its colour and the lower one as its background.
//! Text (HUD, messages) is put on the cells afterwards. No terminal code here: `term.rs` writes the cells.
use crate::art::*;
use crate::game::*;
use std::collections::HashMap;

pub type Rgb = [u8; 3];

#[derive(Clone, Copy, PartialEq)]
pub struct Cell {
    pub ch: char,
    pub fg: Rgb,
    pub bg: Rgb,
}

pub const BLANK: Cell = Cell { ch: ' ', fg: [255, 255, 255], bg: [0, 0, 0] };

/// The cells of the whole window.
pub struct Frame {
    pub cols: usize,
    pub rows: usize,
    pub cells: Vec<Cell>,
}

impl Frame {
    pub fn new(cols: usize, rows: usize) -> Frame {
        Frame { cols, rows, cells: vec![BLANK; cols * rows] }
    }

    /// Put text at a cell (the background stays, unless `bg` is given).
    pub fn text(&mut self, col: i32, row: i32, s: &str, fg: Rgb, bg: Option<Rgb>) {
        if row < 0 || row as usize >= self.rows {
            return;
        }
        for (i, ch) in s.chars().enumerate() {
            let c = col + i as i32;
            if c < 0 || c as usize >= self.cols {
                continue;
            }
            let cell = &mut self.cells[row as usize * self.cols + c as usize];
            cell.ch = ch;
            cell.fg = fg;
            if let Some(b) = bg {
                cell.bg = b;
            }
        }
    }

    pub fn ctext(&mut self, row: i32, s: &str, fg: Rgb, bg: Option<Rgb>) {
        let col = (self.cols as i32 - s.chars().count() as i32) / 2;
        self.text(col, row, s, fg, bg);
    }
}

/// The frame for a window that is too small for the game: a message.
pub fn too_small(cols: usize, rows: usize) -> Frame {
    let mut f = Frame::new(cols, rows);
    f.ctext((rows / 2) as i32, &format!("Please make the window at least {} x {} (now {} x {})", MIN_COLS, MIN_ROWS, cols, rows), [255, 255, 255], None);
    f
}

/// How the play area fits the window: k game pixels for one canvas pixel.
#[derive(Clone, Copy, PartialEq, Debug)]
pub struct Layout {
    pub k: i32,
    pub w: usize, // canvas width in pixels
    pub h: usize, // canvas height in pixels (even)
    pub col0: usize,
    pub row0: usize, // the first rows are the HUD
}

pub const HUD_ROWS: usize = 2;

/// The smallest scale (the biggest picture) that fits the window, or None when the window is too small.
pub fn layout(cols: usize, rows: usize) -> Option<Layout> {
    for k in [2, 3, 4] {
        let w = (320 + k - 1) / k as usize;
        let h = ((200 + k - 1) / k as usize + 1) & !1;
        if cols >= w && rows >= h / 2 + HUD_ROWS {
            return Some(Layout { k: k as i32, w, h, col0: (cols - w) / 2, row0: HUD_ROWS });
        }
    }
    None
}

/// Sizes of the smallest window: 80 x 27 cells.
pub const MIN_COLS: usize = 80;
pub const MIN_ROWS: usize = 27;

pub struct Canvas {
    pub w: usize,
    pub h: usize,
    pub px: Vec<Rgb>,
}

impl Canvas {
    fn new(w: usize, h: usize) -> Canvas {
        Canvas { w, h, px: vec![[0, 0, 0]; w * h] }
    }
    fn set(&mut self, x: i32, y: i32, c: Rgb) {
        if x >= 0 && y >= 0 && (x as usize) < self.w && (y as usize) < self.h {
            self.px[y as usize * self.w + x as usize] = c;
        }
    }
    fn blend(&mut self, x: i32, y: i32, c: Rgb, a: u32) {
        if x >= 0 && y >= 0 && (x as usize) < self.w && (y as usize) < self.h {
            let p = &mut self.px[y as usize * self.w + x as usize];
            for i in 0..3 {
                p[i] = ((p[i] as u32 * (256 - a) + c[i] as u32 * a) >> 8) as u8;
            }
        }
    }
    fn rect(&mut self, x: i32, y: i32, w: i32, h: i32, c: Rgb) {
        for yy in y..y + h {
            for xx in x..x + w {
                self.set(xx, yy, c);
            }
        }
    }
}

// ---- sprites: our own 16 x 16 art (art.rs), reduced to the size of the canvas ----
type Variant = [Rgb; 3];
const V_BEE: Variant = [[70, 130, 255], [150, 200, 255], [30, 60, 190]];
const V_BFLY: Variant = [[255, 60, 60], [255, 150, 130], [160, 20, 40]];
const V_BOSS: Variant = [[60, 220, 90], [170, 255, 160], [20, 130, 50]];
const V_BOSSP: Variant = [[170, 80, 255], [215, 165, 255], [100, 40, 170]];

fn letter_color(ch: u8, v: &Variant) -> Option<Rgb> {
    Some(match ch {
        b'm' => v[0],
        b'M' => v[1],
        b'n' => v[2],
        b'y' => [255, 220, 60],
        b'Y' => [200, 140, 20],
        b'c' => [80, 230, 255],
        b'w' => [255, 255, 255],
        b'k' => [25, 25, 50],
        b'o' => [255, 140, 30],
        b'r' => [255, 60, 60],
        b'b' => [60, 110, 255],
        b'g' => [170, 170, 190],
        _ => return None,
    })
}

/// A picture from the art rows: the left half is mirrored; reduced to `size` x `size` pixels (None: clear).
fn scale_art(rows: &[&str; 16], v: &Variant, size: usize) -> Vec<Option<Rgb>> {
    let mut full = [[None::<Rgb>; 16]; 16];
    for (y, row) in rows.iter().enumerate() {
        let b = row.as_bytes();
        for x in 0..16 {
            full[y][x] = letter_color(if x < 8 { b[x] } else { b[15 - x] }, v);
        }
    }
    let mut out = vec![None; size * size];
    if size >= 16 {
        for ty in 0..size {
            for tx in 0..size {
                out[ty * size + tx] = full[ty * 16 / size][tx * 16 / size];
            }
        }
        return out;
    }
    for ty in 0..size {
        for tx in 0..size {
            let (mut n, mut opaque, mut sum) = (0u32, 0u32, [0u32; 3]);
            for sy in 0..16 {
                for sx in 0..16 {
                    if sy * size / 16 == ty && sx * size / 16 == tx {
                        n += 1;
                        if let Some(c) = full[sy][sx] {
                            opaque += 1;
                            for i in 0..3 {
                                sum[i] += c[i] as u32;
                            }
                        }
                    }
                }
            }
            if n > 0 && opaque * 2 >= n {
                out[ty * size + tx] = Some([(sum[0] / opaque) as u8, (sum[1] / opaque) as u8, (sum[2] / opaque) as u8]);
            }
        }
    }
    out
}

#[derive(Clone, Copy, PartialEq, Eq, Hash)]
enum Spr {
    Bee(usize),
    Bfly(usize),
    Boss(usize),
    BossP(usize),
    Player,
    Xa(usize),
    Xp(usize),
}

fn art_of(s: Spr) -> (&'static [&'static str; 16], &'static Variant) {
    match s {
        Spr::Bee(f) => (if f == 0 { &ART_BEE_A } else { &ART_BEE_B }, &V_BEE),
        Spr::Bfly(f) => (if f == 0 { &ART_BFLY_A } else { &ART_BFLY_B }, &V_BFLY),
        Spr::Boss(f) => (if f == 0 { &ART_BOSS_A } else { &ART_BOSS_B }, &V_BOSS),
        Spr::BossP(f) => (if f == 0 { &ART_BOSS_A } else { &ART_BOSS_B }, &V_BOSSP),
        Spr::Player => (&ART_PLAYER, &V_BEE),
        Spr::Xa(f) => ([&ART_XA0, &ART_XA1, &ART_XA2][f], &V_BEE),
        Spr::Xp(f) => ([&ART_XP0, &ART_XP1, &ART_XP2, &ART_XP3][f], &V_BEE),
    }
}

/// The renderer: the scale, the sprites reduced to it, and the little state a picture needs.
pub struct Renderer {
    pub layout: Layout,
    cache: HashMap<(Spr, usize), Vec<Option<Rgb>>>,
}

impl Renderer {
    pub fn new(layout: Layout) -> Renderer {
        Renderer { layout, cache: HashMap::new() }
    }

    /// Draw a sprite `gsize` game pixels wide with its centre at the game coordinates (cx, cy).
    fn sprite(&mut self, cv: &mut Canvas, s: Spr, cx: i32, cy: i32, gsize: i32) {
        let k = self.layout.k;
        let size = ((gsize + k / 2) / k).max(2) as usize;
        let pic = self.cache.entry((s, size)).or_insert_with(|| {
            let (rows, v) = art_of(s);
            scale_art(rows, v, size)
        });
        let x0 = (cx - 24) / k - size as i32 / 2;
        let y0 = (cy - 50) / k - size as i32 / 2;
        for ty in 0..size {
            for tx in 0..size {
                if let Some(c) = pic[ty * size + tx] {
                    cv.set(x0 + tx as i32, y0 + ty as i32, c);
                }
            }
        }
    }

    fn fighter(&mut self, cv: &mut Canvas, x: i32, y: i32) {
        self.sprite(cv, Spr::Player, x + 12, y + 7, 24);
    }

    fn stars(&self, cv: &mut Canvas, frame: i32) {
        let k = self.layout.k;
        for i in 0..70u32 {
            let h = i.wrapping_mul(2654435761);
            let layer = if i < 8 { 0 } else if i < 24 { 1 } else if i < 48 { 2 } else { 3 };
            let speed = [100, 60, 40, 25][layer]; // 1/100 game pixel a tick
            let x = ((h >> 8) % 320) as i32 / k;
            let y = ((((h >> 20) % 200) as i32 * 100 + frame * speed) % 20000) / 100 / k;
            let b = [230u32, 180, 130, 90][layer];
            let tw = 70 + ((frame as u32 / 6 + i * 7) % 4) * 10; // twinkle
            let v = (b * tw / 100) as u8;
            let col = if i % 5 == 0 { [v, v * 3 / 4, v / 3] } else if i % 7 == 0 { [v / 2, v * 3 / 4, v] } else { [v, v, v] };
            cv.set(x, y, col);
        }
    }

    fn beam(&self, cv: &mut Canvas, g: &Game) {
        let b = &g.al[g.cap_boss as usize];
        let n = if g.cap == C_BEAM { g.beam_len } else { 4 };
        let k = self.layout.k;
        const PULSE: [Rgb; 4] = [[40, 90, 255], [100, 170, 255], [80, 230, 255], [100, 170, 255]];
        for r in 0..n {
            let c = PULSE[((r + (g.frame >> 2)) & 3) as usize];
            let y0 = b.y + 14 + r * 8;
            let (hw0, hw1) = ((2 + r) * 4 + 4, (3 + r) * 4 + 4);
            for gy in (y0..y0 + 8).step_by(k.max(1) as usize) {
                let hw = hw0 + (hw1 - hw0) * (gy - y0) / 8;
                let (x0, x1) = ((b.x + 12 - hw - 24) / k, (b.x + 12 + hw - 24) / k);
                for x in x0..=x1 {
                    cv.blend(x, (gy - 50) / k, c, if x == x0 || x == x1 { 200 } else { 120 });
                }
            }
        }
    }

    /// The picture of the play area for the state of the game.
    fn draw_world(&mut self, cv: &mut Canvas, g: &Game) {
        let k = self.layout.k;
        // the background: a dark blue that gets darker towards the bottom
        for y in 0..cv.h {
            let t = y as u32 * 255 / cv.h as u32;
            let c = [(6 - 6 * t / 255) as u8, (8 - 8 * t / 255) as u8, (30 - 24 * t / 255) as u8];
            for x in 0..cv.w {
                cv.px[y * cv.w + x] = c;
            }
        }
        self.stars(cv, g.frame);
        if g.state == S_TITLE {
            title_logo(cv);
            return;
        }
        if (g.cap == C_BEAM && g.beam_len > 0) || g.cap == C_PULL {
            self.beam(cv, g);
        }
        let flap = ((g.frame >> 4) & 1) as usize;
        for i in 0..NAL {
            let a = &g.al[i];
            if a.st == A_DEAD || (a.st == A_ENTER && a.ent == 0) {
                continue;
            }
            let (cx, cy) = (a.x + 12, a.y + 6);
            if a.st == A_EXPLODE {
                let f = (2 - (a.timer >> 2)).clamp(0, 2) as usize;
                self.sprite(cv, Spr::Xa(f), cx, cy, 30);
                continue;
            }
            let s = match a.typ {
                T_BOSS => {
                    if a.hp == 1 && g.challenge == 0 { Spr::BossP(flap) } else { Spr::Boss(flap) }
                }
                T_BUTTERFLY => Spr::Bfly(flap),
                _ => Spr::Bee(flap),
            };
            self.sprite(cv, s, cx, cy, if a.typ == T_BOSS { 26 } else { 24 });
            if a.typ == T_BOSS && g.cap == C_CARRY && g.cap_boss == i as i32 && a.y >= 32 {
                self.fighter(cv, a.x, a.y - 16);
            }
        }
        for b in g.ps.iter().filter(|b| b.act != 0) {
            let (x, y) = ((b.x + 9 - 24) / k, (b.y + 6 - 50) / k);
            cv.rect(x, y - 3 / k.max(1), 1, (12 / k).max(2), [220, 250, 255]);
        }
        for b in g.eb.iter().filter(|b| b.act != 0) {
            let (x, y) = ((b.x + 12 - 24) / k, (b.y + 4 - 50) / k);
            cv.rect(x, y - 2, ((4 / k).max(1)) as i32, (10 / k).max(2), [255, 150, 120]);
            cv.set(x, y, [255, 240, 160]);
        }
        // the ship
        let show = matches!(g.state, S_INTRO | S_PLAY | S_RESULT | S_CAPTURED);
        if g.state == S_DYING && g.dying_quiet == 0 {
            let f = (3 - (g.state_timer >> 4)).clamp(0, 3) as usize;
            self.sprite(cv, Spr::Xp(f), g.px + 12 + if g.dual != 0 { 8 } else { 0 }, g.py + 7, 52);
        } else if show && !(g.state == S_PLAY && (g.invuln & 4) != 0) {
            self.fighter(cv, g.px, g.py);
            if g.dual != 0 {
                self.fighter(cv, g.px + 16, g.py);
            }
            if g.cap == C_RESCUE {
                self.fighter(cv, g.rx, g.ry);
            }
        }
    }

    /// Draw the whole window: the play area, the HUD, the messages of the state.
    pub fn draw(&mut self, g: &Game, cols: usize, rows: usize) -> Frame {
        let l = self.layout;
        let mut cv = Canvas::new(l.w, l.h);
        self.draw_world(&mut cv, g);
        let mut f = Frame::new(cols, rows);
        for cy in 0..l.h / 2 {
            for cx in 0..l.w {
                let top = cv.px[(2 * cy) * l.w + cx];
                let bot = cv.px[(2 * cy + 1) * l.w + cx];
                f.cells[(l.row0 + cy) * cols + l.col0 + cx] = Cell { ch: '▀', fg: top, bg: bot };
            }
        }
        draw_text_layer(&mut f, g, &l);
        f
    }
}

/// GALAGA in block letters (our own 5 x 5 letters) across the upper part of the canvas
fn title_logo(cv: &mut Canvas) {
    const G: [&str; 5] = [".###.", "#....", "#.##.", "#...#", ".###."];
    const A: [&str; 5] = [".###.", "#...#", "#####", "#...#", "#...#"];
    const L: [&str; 5] = ["#....", "#....", "#....", "#....", "#####"];
    let word = [G, A, L, A, G, A];
    let ps = (cv.w / 40).max(2) as i32; // the size of one letter pixel
    let total = word.len() as i32 * 6 * ps - ps;
    let (x0, y0) = ((cv.w as i32 - total) / 2, (cv.h as i32) / 8);
    for (n, letter) in word.iter().enumerate() {
        for (ry, row) in letter.iter().enumerate() {
            let t = ry as u32 * 255 / 4;
            let c = [255, (230 - 110 * t / 255) as u8, (70 - 60 * t / 255) as u8];
            for (rx, ch) in row.bytes().enumerate() {
                if ch == b'#' {
                    cv.rect(x0 + (n as i32 * 6 + rx as i32) * ps, y0 + ry as i32 * ps, ps, ps, c);
                }
            }
        }
    }
}

const RED: Rgb = [255, 80, 80];
const WHITE: Rgb = [255, 255, 255];
const YELLOW: Rgb = [255, 220, 60];
const CYAN: Rgb = [80, 230, 255];
const DARK: Rgb = [0, 0, 24];

/// A game row of the C64 screen (0..24, 8 game pixels each) as a row of the window.
fn grow(l: &Layout, row: i32) -> i32 {
    l.row0 as i32 + (row * 8 + 4) / l.k / 2
}

fn draw_text_layer(f: &mut Frame, g: &Game, l: &Layout) {
    let (c0, w) = (l.col0 as i32, l.w as i32);
    if g.state != S_TITLE {
        f.text(c0, 0, "SCORE", RED, Some([0, 0, 0]));
        f.text(c0 + w * 3 / 10, 0, "HI-SCORE", RED, Some([0, 0, 0]));
        f.text(c0 + w * 7 / 10, 0, "STAGE", RED, Some([0, 0, 0]));
        f.text(c0 + w * 85 / 100, 0, "LIVES", RED, Some([0, 0, 0]));
        f.text(c0, 1, &format!("{:06}", g.score), WHITE, Some([0, 0, 0]));
        f.text(c0 + w * 3 / 10, 1, &format!("{:06}", g.hi), WHITE, Some([0, 0, 0]));
        f.text(c0 + w * 7 / 10, 1, &format!("{:02}", g.stage), WHITE, Some([0, 0, 0]));
        f.text(c0 + w * 85 / 100, 1, &"▲".repeat(g.lives.clamp(0, 9) as usize), CYAN, Some([0, 0, 0]));
    }
    let mid = l.row0 as i32 + l.h as i32 / 4;
    match g.state {
        S_TITLE => {
            f.ctext(mid - 4, "T E R M I N A L", CYAN, Some(DARK));
            f.ctext(mid, &format!("HI-SCORE  {:06}", g.hi), WHITE, Some(DARK));
            f.ctext(mid + 4, "PRESS SPACE TO START", YELLOW, Some(DARK));
            f.ctext(mid + 6, "LEFT / RIGHT or A / D: move   SPACE: fire   P: pause   Q: quit", [170, 170, 190], Some(DARK));
        }
        S_INTRO => {
            if g.challenge != 0 {
                f.ctext(grow(l, 16), "CHALLENGING STAGE", WHITE, Some(DARK));
            } else {
                f.ctext(grow(l, 16), &format!("STAGE {:02}", g.stage), WHITE, Some(DARK));
            }
        }
        S_READY => f.ctext(grow(l, 20), "READY", WHITE, Some(DARK)),
        S_DYING if g.dying_quiet != 0 => f.ctext(grow(l, 20), "FIGHTER CAPTURED", RED, Some(DARK)),
        S_RESULT => {
            if g.challenge != 0 {
                f.ctext(grow(l, 9), &format!("NUMBER OF HITS  {:3}", g.chal_hits), WHITE, Some(DARK));
                if g.chal_hits == NAL as i32 {
                    f.ctext(grow(l, 11), "PERFECT!", YELLOW, Some(DARK));
                    f.ctext(grow(l, 13), "BONUS 10000", WHITE, Some(DARK));
                }
            } else {
                let ratio = if g.shots > 0 { (g.hits * 100 / g.shots).min(100) } else { 0 };
                f.ctext(grow(l, 9), &format!("SHOTS  {:3}", g.shots), WHITE, Some(DARK));
                f.ctext(grow(l, 11), &format!("HITS   {:3}", g.hits), WHITE, Some(DARK));
                f.ctext(grow(l, 13), &format!("RATIO  {:3}%", ratio), WHITE, Some(DARK));
            }
        }
        S_GAMEOVER => {
            f.ctext(grow(l, 11), "GAME OVER", WHITE, Some(DARK));
            if g.state_timer == 0 {
                f.ctext(grow(l, 14), "PRESS SPACE", WHITE, Some(DARK));
            }
        }
        _ => {}
    }
    if g.paused != 0 {
        f.ctext(grow(l, 20), "PAUSED", WHITE, Some(DARK));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn layouts() {
        assert_eq!(layout(79, 40), None);
        assert_eq!(layout(80, 26), None);
        assert_eq!(layout(80, 27).unwrap().k, 4);
        assert_eq!(layout(107, 36).unwrap().k, 3);
        assert_eq!(layout(160, 52).unwrap().k, 2);
        assert_eq!(layout(200, 60).unwrap().k, 2);
    }

    #[test]
    fn draws_all_states() {
        for (cols, rows) in [(80, 27), (107, 36), (160, 52)] {
            let l = layout(cols, rows).unwrap();
            let mut r = Renderer::new(l);
            let mut g = Game::new(1234);
            let none = Input::default();
            let press = Input { fire: true, ..Default::default() };
            let f = r.draw(&g, cols, rows);
            assert_eq!(f.cells.len(), cols * rows);
            g.tick(&press, 0);
            for t in 0..3000 {
                let inp = game_autoplay(&g);
                g.tick(if t == 0 { &press } else { &inp }, 0);
                if t % 97 == 0 {
                    let f = r.draw(&g, cols, rows);
                    // the play area has pixels that are not black, and the HUD text is there
                    assert!(f.cells.iter().any(|c| c.ch == '▀' && c.fg != [0, 0, 0]));
                }
            }
            let _ = none;
        }
    }
}
