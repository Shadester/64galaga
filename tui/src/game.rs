//! Galaga game rules: a translation of psp/game.c (the arcade rules, 40 aliens) and psp/game.h.
//! Keep the names and the order of the C code, and check a change with tests/test_lockstep.py.
//! The logic runs at 50 ticks a second in C64 sprite coordinates: the play area is x 24..343, y 50..249, and x / y are the top left
//! corner of a 24 x 21 sprite box.
#![allow(dead_code)]

use crate::arcade_data::*;

pub const NAL: usize = 40;
pub const EBN: usize = 8; // enemy bombs on the screen
pub const TICK_HZ: u64 = 50;

pub const S_TITLE: i32 = 0;
pub const S_INTRO: i32 = 1;
pub const S_PLAY: i32 = 2;
pub const S_DYING: i32 = 3;
pub const S_GAMEOVER: i32 = 4;
pub const S_CAPTURED: i32 = 5;
pub const S_RESULT: i32 = 6;
pub const S_READY: i32 = 7;

pub const T_BOSS: i32 = 0;
pub const T_BUTTERFLY: i32 = 1;
pub const T_BEE: i32 = 2;

pub const A_DEAD: i32 = 0;
pub const A_FORM: i32 = 1;
pub const A_DIVE: i32 = 2;
pub const A_RETURN: i32 = 3;
pub const A_EXPLODE: i32 = 4;
pub const A_BEAM: i32 = 5;
pub const A_ENTER: i32 = 6;

/// cap: tractor beam / captive state
pub const C_NONE: i32 = 0;
pub const C_DIVING: i32 = 1;
pub const C_BEAM: i32 = 2;
pub const C_PULL: i32 = 3;
pub const C_CARRY: i32 = 4;
pub const C_RESCUE: i32 = 5;

/// Sound events, one bit each; the platform clears Game.snd after reading.
pub const SND_SHOOT: i32 = 1;
pub const SND_EXPLODE: i32 = 2;
pub const SND_HIT: i32 = 4;
pub const SND_DEATH: i32 = 8;
pub const SND_SWOOP: i32 = 16;
pub const JG_STAGE: i32 = 32;
pub const JG_OVER: i32 = 64;
pub const JG_CAPTURE: i32 = 128;
pub const JG_RESCUE: i32 = 256;
pub const JG_BONUS: i32 = 512;

/// the arcade limits the sideways speed of a bomb to 0.6 of its fall speed (2.5 px a tick): 0.6 x 2.5 x 16
const BOMB_MAX_DX: i32 = 24;
/// A diver drops no bombs below this line. In the arcade it is 97 of the 288 screen lines above the ship (a third of the screen),
/// so a bomb always falls far: here 67 of 200 lines.
const BOMB_LOW_Y: i32 = 163;

const ARC_BEE_FROM: usize = 20; // the slots of the kinds, and the six butterflies that escort a boss
const ARC_BEE_TO: usize = 40;
const ARC_RED_FROM: usize = 4;
const ARC_RED_TO: usize = 20;
const ARC_PEEL: i32 = 0; // ticks a diver waits in its slot before it dives (an escort: 1 and 2 ticks after its boss)

#[derive(Clone, Copy, Default)]
pub struct Alien {
    pub x: i32,
    pub y: i32,
    pub st: i32,
    pub typ: i32,
    pub hp: i32,
    pub timer: i32,
    pub dir: i32,
    pub esc: i32,
    pub capdive: i32,
    pub path: i32,
    pub pstep: i32,
    pub mir: i32,
    pub ent: i32, // 0 waiting, 1 on path, 2 homing
    pub dly: i32,
    pub bflags: i32, // bomb flags
    pub btmr: i32,   // the time to the next bomb (arcade frames)
    pub dpath: i32,  // dive path (-1: free)
}

/// ax: the sideways speed of a bomb is dx / 16 pixel a tick, ax the rest
#[derive(Clone, Copy, Default)]
pub struct Bullet {
    pub x: i32,
    pub y: i32,
    pub act: i32,
    pub dx: i32,
    pub ax: i32,
}

/// pause / quit are edge pulses
#[derive(Clone, Copy, Default)]
pub struct Input {
    pub left: bool,
    pub right: bool,
    pub fire: bool,
    pub pause: bool,
    pub quit: bool,
}

#[derive(Clone)]
pub struct Game {
    pub state: i32,
    pub paused: i32,
    pub state_timer: i32,
    pub frame: i32,
    pub prev_fire: i32,
    pub score: i32,
    pub hi: i32,
    pub lives: i32,
    pub stage: i32,
    pub diff: i32,
    pub next_bonus: i32,
    pub challenge: i32,
    pub chal_val: i32,
    pub chal_hits: i32,
    pub chal_timer: i32,
    pub shots: i32,
    pub hits: i32,
    pub px: i32,
    pub py: i32,
    pub invuln: i32,
    pub dual: i32,
    pub dying_quiet: i32,
    pub form_dx: i32,
    pub form_dir: i32,
    pub form_timer: i32,
    pub entering: i32,
    pub cap: i32,
    pub cap_boss: i32,
    pub beam_len: i32,
    pub beam_acc: i32,
    pub beam_timer: i32,
    pub rx: i32,
    pub ry: i32,
    pub snd: i32,
    pub save_req: i32,
    pub al: [Alien; NAL],
    // the dive scheduler runs on the arcade's 60 Hz clock: 6 arcade frames for every 5 ticks
    pub beam_ph: i32, // the beam: 0 grows, 1 holds (the ship is taken), 2 shrinks
    pub beam_step: i32, // ticks for one of its 4 steps
    pub clk: i32,
    pub af: i32,
    pub tmr2: i32, // counts down from 120 once in 32 frames (time since the stage began)
    pub hold: i32, // no bombs after a boss was shot while it dived
    pub sortie: [i32; 3],
    pub wingm: i32,
    pub bomb_flags: i32,
    // the formation: swing while the aliens fly in, then breathe (also on the arcade clock)
    pub fclk: i32,
    pub ff: i32,
    pub sway_pos: i32,
    pub sway_dir: i32,
    pub breathe: i32,
    pub bstep: i32,
    pub ps: [Bullet; 4],
    pub eb: [Bullet; EBN],
}

pub fn slot_x(i: usize) -> i32 {
    ARC_SLOT[i][0]
}
pub fn slot_y(i: usize) -> i32 {
    ARC_SLOT[i][1]
}

/// where a slot is now: the swing of the whole formation and the breathing of its columns and rows
fn slot_px(g: &Game, i: usize) -> i32 {
    let mut x = slot_x(i) + g.form_dx;
    let c = ARC_SLOT_COL[i] as usize;
    if g.breathe != 0 {
        x += if c < 5 { ARC_BREATH[g.bstep as usize][c] } else { -ARC_BREATH[g.bstep as usize][9 - c] };
    }
    x
}
fn slot_py(g: &Game, i: usize) -> i32 {
    slot_y(i) + if g.breathe != 0 { ARC_BREATH[g.bstep as usize][5 + ARC_SLOT_ROW[i] as usize] } else { 0 }
}

/// the arcade repeats stages 23..26 (its tables stop there)
fn arc_stage_no(mut stage: i32) -> usize {
    if stage > ARC_NSTAGE {
        stage = ARC_NSTAGE - 3 + ((stage - (ARC_NSTAGE - 3)) & 3);
    }
    (stage - 1) as usize
}

fn add_score(g: &mut Game, n: i32) {
    g.score += n;
    if g.score > 999999 {
        g.score = 999999;
    }
    if g.score > g.hi {
        g.hi = g.score;
    }
    while g.score >= g.next_bonus {
        if g.lives < 9 {
            g.lives += 1;
        }
        g.next_bonus += if g.next_bonus == 20000 { 50000 } else { 70000 };
        g.snd |= JG_BONUS;
    }
}

fn setup_stage(g: &mut Game) {
    let row = ARC_STAGE[arc_stage_no(g.stage)][0] as usize;
    g.challenge = ARC_ROW[row].challenge as i32;
    g.chal_val = 100; // 100 for each enemy, 10,000 when all are hit (public descriptions of the arcade; not checked in the model)
    g.chal_hits = 0;
    g.chal_timer = 0;
    g.shots = 0;
    g.hits = 0;
    g.fclk = 0;
    g.ff = 0;
    g.sway_pos = 0;
    g.breathe = 0;
    g.bstep = 0;
    g.sway_dir = 1;
    g.form_dx = 0;
    g.form_dir = 3;
    g.form_timer = 0;
    g.clk = 0;
    g.af = 0;
    g.wingm = 0;
    g.bomb_flags = 0;
    g.hold = 0;
    g.tmr2 = 120;
    g.sortie = [22, 2, 2];
    g.cap = C_NONE;
    g.beam_len = 0;
    g.ps = [Bullet::default(); 4];
    g.eb = [Bullet::default(); EBN];
    for i in 0..NAL {
        let mut a = Alien::default();
        a.typ = if i < 4 { T_BOSS } else if i < 20 { T_BUTTERFLY } else { T_BEE };
        a.hp = if g.challenge == 0 && a.typ == T_BOSS { 2 } else { 1 };
        a.st = A_ENTER;
        a.y = 255;
        g.al[i] = a;
    }
    // the launch list of the stage's row: when each slot starts, and on which path (slot -1: an extra enemy, not used yet)
    for l in ARC_ROW[row].l.iter() {
        if l[1] >= 0 {
            let a = &mut g.al[l[1] as usize];
            a.dly = l[0];
            a.path = l[2];
            a.bflags = if ARC_ENTRY_BOMB[l[1] as usize] != 0 { ARC_ROW[row].hdr1 } else { 0 };
            a.btmr = ARC_PATH[l[2] as usize].bt; // the bombs of an enemy that flies in
        }
    }
}

fn start_stage(g: &mut Game) {
    setup_stage(g);
    g.state = S_INTRO;
    g.state_timer = 120;
    g.snd |= JG_STAGE;
}

fn start_game(g: &mut Game, start_stage_no: i32) {
    g.score = 0;
    g.lives = 3;
    g.stage = 1;
    g.diff = 1;
    if start_stage_no > 0 {
        g.stage = start_stage_no;
        g.diff = 1 + (g.stage - 1 - g.stage / 4);
        if g.diff > 8 {
            g.diff = 8;
        }
    }
    g.next_bonus = 20000;
    g.dual = 0;
    g.cap = C_NONE;
    g.px = 160;
    g.py = 230;
    g.invuln = 0;
    g.dying_quiet = 0;
    start_stage(g);
}

fn game_over(g: &mut Game) {
    g.state = S_GAMEOVER;
    g.state_timer = 90;
    g.snd |= JG_OVER;
    g.save_req = 1;
}

impl Game {
    pub fn new(hi_score: i32) -> Game {
        Game {
            state: S_TITLE,
            paused: 0,
            state_timer: 0,
            frame: 0,
            prev_fire: 0,
            score: 0,
            hi: hi_score,
            lives: 0,
            stage: 0,
            diff: 0,
            next_bonus: 0,
            challenge: 0,
            chal_val: 0,
            chal_hits: 0,
            chal_timer: 0,
            shots: 0,
            hits: 0,
            px: 160,
            py: 230,
            invuln: 0,
            dual: 0,
            dying_quiet: 0,
            form_dx: 0,
            form_dir: 0,
            form_timer: 0,
            entering: 0,
            cap: 0,
            cap_boss: 0,
            beam_len: 0,
            beam_acc: 0,
            beam_timer: 0,
            rx: 0,
            ry: 0,
            snd: 0,
            save_req: 0,
            al: [Alien::default(); NAL],
            beam_ph: 0,
            beam_step: 0,
            clk: 0,
            af: 0,
            tmr2: 0,
            hold: 0,
            sortie: [0; 3],
            wingm: 0,
            bomb_flags: 0,
            fclk: 0,
            ff: 0,
            sway_pos: 0,
            sway_dir: 0,
            breathe: 0,
            bstep: 0,
            ps: [Bullet::default(); 4],
            eb: [Bullet::default(); EBN],
        }
    }
}

// ---- player ----
fn player_hit(g: &mut Game, side: i32) {
    if g.dual != 0 {
        g.dual = 0;
        if side == 0 {
            g.px += 16;
        }
        g.invuln = 90;
        g.snd |= SND_HIT;
        return;
    }
    g.lives -= 1;
    g.state = S_DYING;
    g.dying_quiet = 0;
    g.state_timer = 107; // the arcade waits 4 x 32 frames before the ship comes back
    g.eb = [Bullet::default(); EBN];
    g.ps = [Bullet::default(); 4];
    g.snd |= SND_HIT | SND_DEATH;
}

fn update_player(g: &mut Game, inp: &Input, fire_press: bool) {
    let maxx = if g.dual != 0 { 304 } else { 320 };
    if inp.left {
        g.px -= 2;
    }
    if inp.right {
        g.px += 2;
    }
    if g.px < 24 {
        g.px = 24;
    }
    if g.px > maxx {
        g.px = maxx;
    }
    if !fire_press {
        return;
    }
    let ships = if g.dual != 0 { 2 } else { 1 };
    for n in 0..ships {
        for i in n * 2..n * 2 + 2 {
            if g.ps[i].act == 0 {
                g.ps[i].act = 1;
                g.ps[i].x = g.px + 3 + 16 * n as i32;
                g.ps[i].y = 214;
                if g.state != S_RESULT {
                    g.shots += 1; // the result screen shows the stage's shots: later ones do not count
                }
                g.snd |= SND_SHOOT;
                break;
            }
        }
    }
}

fn update_pshots(g: &mut Game) {
    for i in 0..4 {
        if g.ps[i].act != 0 {
            g.ps[i].y -= 4;
            if g.ps[i].y < 20 {
                g.ps[i].act = 0;
            }
        }
    }
}

// ---- aliens ----
fn release_capture(g: &mut Game, boss: i32) {
    if g.cap != 0 && g.cap != C_RESCUE && g.cap_boss == boss {
        g.cap = C_NONE;
    }
}

fn alien_hit(g: &mut Game, i: usize) {
    let a = g.al[i];
    let dive = a.st == A_DIVE || a.st == A_ENTER;
    let mut pts;
    g.hits += 1;
    if a.hp > 1 {
        g.al[i].hp -= 1;
        g.snd |= SND_SHOOT;
        return;
    }
    if g.challenge != 0 {
        g.chal_hits += 1;
        pts = g.chal_val;
    } else if a.typ == T_BOSS {
        let mut n = 0;
        if dive {
            for k in 0..NAL {
                n += (g.al[k].esc == i as i32 + 1 && (g.al[k].st == A_DIVE || g.al[k].st == A_RETURN)) as i32;
            }
        }
        pts = if dive { 400 << n } else { 150 };
        if dive {
            g.hold = 6;
        }
    } else {
        pts = if a.typ == T_BUTTERFLY {
            if dive { 160 } else { 80 }
        } else if dive {
            100
        } else {
            50
        };
    }
    if a.typ == T_BOSS && g.cap != 0 && g.cap_boss == i as i32 {
        if g.cap == C_CARRY && (a.st == A_DIVE || a.st == A_RETURN) {
            g.cap = C_RESCUE;
            g.rx = a.x;
            g.ry = a.y - 16;
            pts += 1000;
            g.snd |= JG_RESCUE;
        } else {
            g.cap = C_NONE; // captive lost, or capture cancelled (beam vanishes)
        }
    }
    g.al[i].st = A_EXPLODE;
    g.al[i].timer = 11;
    g.snd |= SND_EXPLODE;
    add_score(g, pts);
}

/// mirrored paths are separate paths: no mirror here
fn path_step(a: &mut Alien) {
    let d = ARC_PATH[a.path as usize].d;
    let k = 2 * a.pstep as usize;
    a.x += d[k] as i32;
    a.y += d[k + 1] as i32;
    a.pstep += 1;
}

fn path_launch(a: &mut Alien) {
    a.ent = 1;
    a.pstep = 0;
    a.x = ARC_PATH[a.path as usize].sx;
    a.y = ARC_PATH[a.path as usize].sy;
}

/// The formation swings left and right while the aliens fly in (one arcade pixel every 4 frames, +-32), and when they are all home and
/// the swing comes back to the middle it starts to breathe (arc_breath).
fn arc_form_frame(g: &mut Game) {
    g.ff += 1;
    if g.breathe != 0 {
        if g.ff & 3 == 0 {
            g.bstep = (g.bstep + 1) & 63;
        }
        return;
    }
    if (g.ff - 1) & 3 != 0 {
        return;
    }
    g.sway_pos += g.sway_dir;
    if g.entering == 0 && g.sway_pos == 0 {
        g.breathe = 1;
        g.bstep = 0;
    } else if g.sway_pos >= 32 {
        g.sway_dir = -1;
    } else if g.sway_pos <= -32 {
        g.sway_dir = 1;
    }
    g.form_dx = g.sway_pos + g.sway_pos * 3 / 7; // 320 / 224
}

fn update_formation(g: &mut Game) {
    let n = g.al.iter().filter(|a| a.st == A_ENTER).count() as i32;
    g.entering = n;
    if g.challenge != 0 {
        return;
    }
    g.fclk += 6;
    while g.fclk >= 5 {
        arc_form_frame(g);
        g.fclk -= 5;
    }
}

fn update_entry(g: &mut Game) {
    for i in 0..NAL {
        if g.al[i].st != A_ENTER {
            continue;
        }
        if g.al[i].ent == 0 {
            if g.state != S_PLAY {
                continue; // the waves wait while the ship is dead or taken: the aliens in the air finish, the others do not start
            }
            g.al[i].dly -= 1;
            if g.al[i].dly <= 0 {
                path_launch(&mut g.al[i]);
            }
        } else if g.al[i].ent == 1 {
            if g.al[i].pstep >= ARC_PATH[g.al[i].path as usize].n {
                g.al[i].ent = 2;
            } else {
                path_step(&mut g.al[i]);
            }
        } else {
            let tx = slot_px(g, i);
            let ty = slot_py(g, i);
            let a = &mut g.al[i];
            a.x += if a.x < tx { 2 } else if a.x > tx { -2 } else { 0 };
            a.y += if a.y < ty { 2 } else if a.y > ty { -2 } else { 0 };
            if (a.x - tx).abs() <= 3 && (a.y - ty).abs() <= 3 {
                a.st = A_FORM;
                a.x = tx;
                a.y = ty;
            }
        }
    }
}

fn update_challenge(g: &mut Game) {
    g.chal_timer += 1;
    for i in 0..NAL {
        let a = &mut g.al[i];
        if a.st != A_ENTER {
            continue;
        }
        if a.ent == 0 {
            if g.chal_timer >= a.dly {
                path_launch(a);
            }
        } else if a.pstep >= ARC_PATH[a.path as usize].n {
            a.st = A_DEAD;
        } else {
            path_step(a);
        }
    }
}

/// Drop a bomb from the place of an alien (x, y)
fn spawn_ebullet(g: &mut Game, ax: i32, ay: i32) {
    let d = g.px - ax;
    for i in 0..EBN {
        if g.eb[i].act == 0 {
            g.eb[i].act = 1;
            g.eb[i].x = ax;
            g.eb[i].y = ay + 8;
            // aimed at the ship's place now: the bomb needs (py - y) / 2.5 ticks to fall, so it moves dx / ticks a tick, in 16ths
            g.eb[i].ax = 0;
            g.eb[i].dx = 16 * d / ((g.py - g.eb[i].y) * 2 / 5 + 1);
            if g.eb[i].dx > BOMB_MAX_DX {
                g.eb[i].dx = BOMB_MAX_DX;
            }
            if g.eb[i].dx < -BOMB_MAX_DX {
                g.eb[i].dx = -BOMB_MAX_DX;
            }
            return;
        }
    }
}

fn start_dive(g: &mut Game, i: usize, capture: i32, peel: i32) {
    let px = g.px;
    let bomb_flags = g.bomb_flags;
    let a = &mut g.al[i];
    a.st = A_DIVE;
    a.timer = peel;
    a.capdive = capture;
    a.dir = if capture != 0 {
        if a.x < px { 1 } else { -1 }
    } else if a.x >= 184 {
        1
    } else {
        -1
    };
    g.snd |= SND_SWOOP;
    if capture != 0 {
        g.cap = C_DIVING;
        g.cap_boss = i as i32;
    }
    let a = &mut g.al[i];
    a.bflags = bomb_flags;
    a.btmr = 30;
    // a dive follows the arcade path of its kind from its slot: a boss and an escort label 2, a butterfly 1, a bee 0
    a.pstep = 0;
    let label = if a.esc != 0 || a.typ == T_BOSS { 2 } else if a.typ == T_BUTTERFLY { 1 } else { 0 };
    a.dpath = if capture != 0 { -1 } else { ARC_DIVE[label][ARC_SLOT_ROW[i] as usize][ARC_SLOT_SIDE[i] as usize] };
}

/// the capture dive: it steers to the ship, the beam starts at y 196
fn dive_step_old(g: &mut Game, i: usize) {
    let diff = g.diff;
    let px = g.px;
    let odd_frame = g.frame & 1 != 0;
    let beam_step = ARC_STAGE[arc_stage_no(g.stage)][1 + 6] * 10 * 5 / 6 / 4;
    let a = &mut g.al[i];
    let dy = if diff >= 5 { 3 } else { 2 };
    if a.timer > 0 {
        a.timer -= 1;
        a.x += 2 * a.dir;
        a.y += 1;
        return;
    }
    a.y += dy;
    if a.capdive != 0 || odd_frame {
        a.x += if a.x < px { 1 } else if a.x > px { -1 } else { 0 };
    }
    if a.capdive != 0 && a.y >= 196 {
        a.st = A_BEAM;
        g.cap = C_BEAM;
        g.beam_len = 0;
        g.beam_acc = 0;
        g.beam_timer = 180;
        // 10 x p6 arcade frames to grow (p6 = 12, 9 or 6 by stage), then 64 frames to take the ship, then the same to go
        g.beam_ph = 0;
        g.beam_step = beam_step;
    } else if a.y >= 244 {
        a.st = A_RETURN;
        a.y = 0;
        a.capdive = 0;
    }
}

fn dive_step(g: &mut Game, i: usize) {
    if g.al[i].capdive != 0 {
        dive_step_old(g, i);
        return;
    }
    if g.al[i].timer > 0 {
        let x = slot_px(g, i);
        let y = slot_py(g, i);
        let a = &mut g.al[i];
        a.timer -= 1;
        a.x = x; // an escort waits for its boss
        a.y = y;
        return;
    }
    let px = g.px;
    let odd_frame = g.frame & 1 != 0;
    let sy = slot_py(g, i);
    let a = &mut g.al[i];
    if a.dpath >= 0 && a.pstep < ARC_DIVE_PATH[a.dpath as usize].n {
        let d = ARC_DIVE_PATH[a.dpath as usize].d;
        let k = 2 * a.pstep as usize;
        a.x += d[k] as i32;
        a.y += d[k + 1] as i32;
    } else {
        // the end of the arcade path of a butterfly (it aims at the ship)
        a.y += 3;
        if odd_frame {
            a.x += if a.x < px { 1 } else if a.x > px { -1 } else { 0 };
        }
    }
    a.pstep += 1;
    if a.y >= 244 {
        // gone below the screen: back from the top when the arcade dive would end (the way back takes slot_y / 2 ticks)
        let total = if a.dpath >= 0 { ARC_DIVE_PATH[a.dpath as usize].total } else { 220 };
        a.st = A_RETURN;
        a.y = 0;
        a.timer = total - a.pstep - sy / 2;
        if a.timer < 0 {
            a.timer = 0;
        }
    }
}

fn update_aliens(g: &mut Game) {
    for i in 0..NAL {
        match g.al[i].st {
            A_FORM => {
                let x = slot_px(g, i);
                let y = slot_py(g, i);
                let a = &mut g.al[i];
                a.x = x;
                a.y = y;
                if a.timer > 0 {
                    a.timer -= 1; // just home: it turns round before it can dive again
                }
            }
            A_EXPLODE => {
                g.al[i].timer -= 1;
                if g.al[i].timer < 0 {
                    g.al[i].st = A_DEAD;
                }
            }
            A_DIVE => dive_step(g, i),
            A_RETURN => {
                let x = slot_px(g, i);
                let sy = slot_py(g, i);
                let a = &mut g.al[i];
                a.x = x;
                if a.timer > 0 {
                    a.timer -= 1;
                    continue;
                }
                a.y += 2;
                if a.y >= sy {
                    a.y = sy;
                    a.st = A_FORM;
                    a.esc = 0;
                    a.timer = if a.typ == T_BEE { 3 } else { 45 }; // the arcade takes 54 frames (bee: 3) to settle a boss or a butterfly: 45 ticks
                }
            }
            _ => {}
        }
    }
}

/// The first alien of a kind that is at home and has settled
fn arc_standby(g: &Game, from: usize, to: usize) -> i32 {
    for i in from..to {
        if g.al[i].st == A_FORM && g.al[i].timer == 0 {
            return i as i32;
        }
    }
    -1
}

/// case_bmbr_boss, j_1CAE: who dives with whom (see ARCADE.md)
fn arc_sortie_boss(g: &mut Game) {
    const BOSS_FOR_B: [usize; 5] = [0, 1, 3, 2, 0];
    let mut c: i32 = 0;
    let mut slot: i32 = -1;
    let mut n = 1;
    let mut esc = [0usize; 2];
    let mut ne = 0;
    if g.cap == 0 {
        // every second sortie tries to capture
        g.wingm += 1;
        if g.wingm & 1 == 0 && g.dual == 0 {
            slot = arc_standby(g, 0, 4);
            if slot >= 0 {
                start_dive(g, slot as usize, 1, 20);
            }
            return;
        }
    }
    for k in 0..6 {
        let w = ARC_WINGMEN[k] as usize;
        c = (c << 1) | (g.al[w].st == A_FORM && g.al[w].timer == 0) as i32; // which of the six wingmen are at home
    }
    let mut cc = 0;
    let mut bb = 0;
    let mut ixl = 0;
    while ixl < 2 && slot < 0 {
        // ixl 0: a boss with two wingmen (the pattern 011, 111, 110), ixl 1: with one
        cc = c;
        bb = 4;
        while bb >= 1 {
            let a = cc & 7;
            let boss = BOSS_FOR_B[bb as usize];
            if (if ixl == 0 { a != 4 && a >= 3 } else { a != 0 }) && g.al[boss].st == A_FORM && g.al[boss].timer == 0 {
                slot = boss as i32;
                n = 2 - ixl;
                break;
            }
            bb -= 1;
            cc >>= 1;
        }
        ixl += 1;
    }
    if slot < 0 {
        // a boss alone
        slot = arc_standby(g, 0, 4);
        if slot >= 0 {
            start_dive(g, slot as usize, 0, ARC_PEEL);
        }
        return;
    }
    let mut b = bb + 1; // B and cc are the ones of the match
    for _ in 0..n {
        let mut cy = cc & 1;
        cc = (cc >> 1) | (cy << 7);
        if cy == 0 {
            b -= 1;
            cy = cc & 1;
            cc = (cc >> 1) | (cy << 7);
            if cy == 0 {
                b -= 1;
            }
        }
        if (0..6).contains(&b) {
            esc[ne] = ARC_WINGMEN[b as usize] as usize;
            ne += 1;
        }
        b -= 1;
    }
    for k in 0..ne {
        g.al[esc[k]].esc = slot + 1;
    }
    start_dive(g, slot as usize, 0, ARC_PEEL);
    for k in 0..ne {
        start_dive(g, esc[k], 0, k as i32 + 1);
    }
}

/// The arcade's dive scheduler (f_0857, f_1B65 of the model, see ARCADE.md). One call is one arcade frame.
fn arc_frame(g: &mut Game) {
    let st = ARC_STAGE[arc_stage_no(g.stage)];
    let p = |k: usize| st[1 + k] as usize; // the parameters p0.. of the stage
    let hdr0 = ARC_ROW[st[0] as usize].hdr0;
    let mut n: i32 = 0;
    let mut flying: i32 = 0;
    let mut maxb = p(4) as i32;
    g.af += 1;
    if g.af & 31 == 0 {
        if g.tmr2 > 0 {
            g.tmr2 -= 1;
        }
        if g.hold > 0 {
            g.hold -= 1;
        }
    }
    for a in g.al.iter() {
        n += (a.st != A_DEAD && a.st != A_EXPLODE) as i32;
        flying += (a.st == A_DIVE || a.st == A_RETURN || a.st == A_BEAM) as i32;
    }
    let tens = (n / 10) as usize;
    if g.tmr2 < 60 {
        maxb = p(5) as i32;
    }
    g.bomb_flags = ARC_BOMB_TAB[4 * p(0) + tens];
    let cont = n < p(7) as i32;
    let idx = (g.tmr2 < 40) as usize + (g.tmr2 == 0) as usize;
    let reload = [
        if cont { 2 } else { ARC_BOMB_TAB[32 + 4 * p(1) + tens] },
        if cont { 2 } else { ARC_RED_RELOAD[3 * p(2) + idx] },
        if cont { 2 } else { ARC_BEE_RELOAD[3 * p(3) + idx] },
    ];
    for i in 0..NAL {
        // bombs: a diver drops one at every set bit of its flags, every 20 frames, high on the screen
        let a = &mut g.al[i];
        if !((a.st == A_DIVE && a.capdive == 0) || (a.st == A_ENTER && a.ent == 1)) {
            continue;
        }
        a.btmr -= 1;
        if a.btmr > 0 {
            continue;
        }
        a.btmr = hdr0;
        let (ax, ay, flag) = (a.x, a.y, a.bflags & 1 != 0);
        if flag && ay <= BOMB_LOW_Y && g.hold == 0 {
            spawn_ebullet(g, ax, ay);
        }
        g.al[i].bflags >>= 1;
    }
    if g.entering != 0 || (g.af & 15) != 0 {
        return;
    }
    let mut i = 0;
    while i < 3 {
        g.sortie[i] -= 1;
        if g.sortie[i] == 0 {
            break;
        }
        i += 1;
    }
    if i == 3 {
        return;
    }
    if flying >= maxb {
        g.sortie[i] += 1;
        return;
    }
    g.sortie[i] = reload[i];
    if i == 2 {
        let n = arc_standby(g, ARC_BEE_FROM, ARC_BEE_TO);
        if n >= 0 {
            start_dive(g, n as usize, 0, ARC_PEEL);
        }
    } else if i == 1 {
        let n = arc_standby(g, ARC_RED_FROM, ARC_RED_TO);
        if n >= 0 {
            start_dive(g, n as usize, 0, ARC_PEEL);
        }
    } else {
        arc_sortie_boss(g);
    }
}

fn select_dive(g: &mut Game) {
    if g.challenge != 0 {
        return;
    }
    g.clk += 6;
    while g.clk >= 5 {
        arc_frame(g);
        g.clk -= 5;
    }
}

fn update_ebullets(g: &mut Game) {
    let frame = g.frame;
    for b in g.eb.iter_mut() {
        if b.act != 0 {
            b.y += 2 + (frame & 1);
            b.ax += b.dx;
            b.x += b.ax >> 4;
            b.ax &= 15;
            if b.y >= 250 {
                b.act = 0;
            }
        }
    }
}

fn update_collisions(g: &mut Game) {
    for i in 0..4 {
        if g.ps[i].act == 0 {
            continue;
        }
        for j in 0..NAL {
            let a = g.al[j];
            if a.st == A_DEAD || a.st == A_EXPLODE || (a.st == A_ENTER && a.ent == 0) {
                continue;
            }
            let (sx, sy) = (g.ps[i].x, g.ps[i].y);
            if sy - 8 <= a.y && a.y < sy + 8 && a.x - 6 <= sx && sx < a.x + 12 {
                g.ps[i].act = 0;
                alien_hit(g, j);
                break;
            }
        }
    }
    if g.state != S_PLAY || g.invuln != 0 {
        return;
    }
    let mut i = 0;
    while i < EBN && g.state == S_PLAY {
        if g.eb[i].act != 0 && g.eb[i].y >= 227 && g.eb[i].y <= 240 {
            for j in 0..1 + g.dual {
                let sx = g.px + 16 * j;
                if g.eb[i].x >= sx - 6 && g.eb[i].x <= sx + 7 {
                    g.eb[i].act = 0;
                    player_hit(g, j);
                    break;
                }
            }
        }
        i += 1;
    }
    let mut j = 0;
    while j < NAL && g.state == S_PLAY && g.invuln == 0 && g.challenge == 0 {
        // challenge aliens never ram
        let a = g.al[j];
        if (a.st == A_DIVE) || (a.st == A_ENTER && a.ent != 0) {
            for s in 0..1 + g.dual {
                let sx = g.px + 16 * s;
                if a.y >= g.py - 7 && a.y <= g.py + 8 && a.x > sx - 8 && a.x <= sx + 8 {
                    if a.capdive != 0 {
                        release_capture(g, j as i32); // ramming boss drops its captive
                    }
                    if a.typ == T_BOSS && g.cap == C_CARRY && g.cap_boss == j as i32 {
                        g.cap = C_NONE;
                    }
                    g.al[j].st = A_EXPLODE;
                    g.al[j].timer = 11;
                    g.snd |= SND_EXPLODE;
                    player_hit(g, s);
                    break;
                }
            }
        }
        j += 1;
    }
}

// ---- tractor beam, capture, rescue ----
fn update_capture(g: &mut Game) {
    if g.cap == C_BEAM {
        let bi = g.cap_boss as usize;
        if g.frame & 31 == 0 {
            g.snd |= SND_SWOOP;
        }
        if g.beam_ph == 0 {
            g.beam_acc += 1;
            if g.beam_acc >= g.beam_step {
                g.beam_acc = 0;
                g.beam_len += 1;
                if g.beam_len >= 4 {
                    g.beam_ph = 1;
                    g.beam_timer = 53;
                }
            }
        } else if g.beam_ph == 2 {
            g.beam_acc += 1;
            if g.beam_acc >= g.beam_step {
                g.beam_acc = 0;
                g.beam_len -= 1;
                if g.beam_len <= 0 {
                    g.cap = C_NONE;
                    g.al[bi].st = A_RETURN;
                    g.al[bi].y = 0;
                }
            }
        } else if g.state == S_PLAY && g.invuln == 0 && g.px >= g.al[bi].x - 20 && g.px <= g.al[bi].x + 19 {
            g.cap = C_PULL;
            g.state = S_CAPTURED;
            g.dual = 0;
            g.ps = [Bullet::default(); 4];
            g.snd |= JG_CAPTURE;
        } else {
            g.beam_timer -= 1;
            if g.beam_timer <= 0 {
                g.beam_ph = 2;
                g.beam_acc = 0;
            }
        }
    } else if g.cap == C_RESCUE {
        let tx = g.px + 16;
        g.ry += 3;
        if g.ry > 230 {
            g.ry = 230;
        }
        g.rx += if g.rx < tx { 2 } else if g.rx > tx { -2 } else { 0 };
        if g.ry == 230 && g.state == S_PLAY && g.rx - tx >= -4 && g.rx - tx <= 3 {
            g.cap = C_NONE;
            g.dual = 1;
            if g.px > 304 {
                g.px = 304;
            }
            g.snd |= JG_RESCUE;
        }
    }
}

fn update_captured(g: &mut Game) {
    let bi = g.cap_boss as usize;
    update_ebullets(g);
    g.py -= 2;
    if g.py - g.al[bi].y >= 22 {
        return;
    }
    g.py = 230;
    g.cap = C_CARRY;
    g.al[bi].st = A_RETURN;
    g.al[bi].y = 0;
    g.al[bi].capdive = 0;
    g.lives -= 1;
    if g.lives <= 0 {
        game_over(g);
        return;
    }
    g.state = S_DYING;
    g.state_timer = 100;
    g.dying_quiet = 1;
}

fn next_stage(g: &mut Game) {
    if g.challenge == 0 && g.diff < 8 {
        g.diff += 1;
    }
    g.stage += 1;
    start_stage(g);
}

fn enter_result(g: &mut Game) {
    g.state = S_RESULT;
    g.state_timer = 150;
    if g.challenge != 0 && g.chal_hits == NAL as i32 {
        add_score(g, 10000);
    }
}

fn move_world(g: &mut Game) {
    update_formation(g);
    update_entry(g);
    update_aliens(g);
}

impl Game {
    /// One tick. `start_stage_no` > 0 starts the game at that stage (a test and debug switch, like START_STAGE in the C code).
    pub fn tick(&mut self, inp: &Input, start_stage_no: i32) {
        let g = self;
        let fire_press = inp.fire && g.prev_fire == 0;
        g.prev_fire = inp.fire as i32;
        if g.state == S_TITLE {
            if fire_press {
                start_game(g, start_stage_no);
            }
            g.frame += 1;
            return;
        }
        if inp.pause && g.state == S_PLAY {
            g.paused = (g.paused == 0) as i32;
        }
        if g.paused != 0 {
            return;
        }
        if inp.quit && g.state != S_GAMEOVER {
            g.state = S_TITLE;
            g.save_req = 1;
            g.snd = 0;
            return;
        }
        g.frame += 1;
        match g.state {
            S_INTRO => {
                g.state_timer -= 1;
                if g.state_timer <= 0 {
                    g.state = S_PLAY;
                }
            }
            S_PLAY => {
                if g.invuln != 0 {
                    g.invuln -= 1;
                }
                update_player(g, inp, fire_press);
                update_pshots(g);
                if g.challenge != 0 {
                    update_challenge(g);
                    update_aliens(g);
                } else {
                    move_world(g);
                    select_dive(g);
                    update_ebullets(g);
                }
                update_collisions(g);
                update_capture(g);
                if g.state != S_PLAY {
                    return;
                }
                let alive = g.al.iter().filter(|a| a.st != A_DEAD).count();
                if alive == 0 && g.cap != C_RESCUE {
                    enter_result(g);
                }
            }
            S_DYING => {
                if g.challenge != 0 {
                    update_aliens(g);
                } else {
                    move_world(g);
                    update_ebullets(g);
                    update_capture(g);
                }
                g.state_timer -= 1;
                if g.state_timer <= 0 {
                    if g.lives <= 0 {
                        game_over(g);
                    } else {
                        g.state = S_READY;
                        g.state_timer = 80; // 3 x 32 frames after the last flyer is home
                    }
                }
            }
            S_READY => {
                if g.challenge != 0 {
                    update_aliens(g);
                } else {
                    move_world(g);
                }
                if g.challenge == 0 {
                    // the ship comes back when nothing flies any more: the divers finish first, the beam too
                    update_capture(g);
                    let flying = g.al.iter().any(|a| a.st == A_DIVE || a.st == A_RETURN || a.st == A_BEAM || (a.st == A_ENTER && a.ent != 0));
                    if flying {
                        return;
                    }
                }
                g.state_timer -= 1;
                if g.state_timer <= 0 {
                    g.state = S_PLAY;
                    g.px = 160;
                    g.invuln = 120;
                    g.tmr2 += 30; // after a death the sorties start slowly again
                    if g.tmr2 > 120 {
                        g.tmr2 = 120;
                    }
                }
            }
            S_CAPTURED => {
                move_world(g);
                update_capture(g);
                update_captured(g);
            }
            S_RESULT => {
                update_player(g, inp, fire_press);
                update_pshots(g);
                g.state_timer -= 1;
                if g.state_timer <= 0 {
                    next_stage(g);
                }
            }
            S_GAMEOVER => {
                if g.state_timer > 0 {
                    g.state_timer -= 1;
                } else if fire_press {
                    g.state = S_TITLE;
                }
            }
            _ => {}
        }
    }
}

/// Synthetic input for unattended runs: sweep, fire, press fire on menus.
pub fn game_autoplay(g: &Game) -> Input {
    let left = (g.frame >> 7) & 1 != 0;
    Input { fire: (g.frame & 15) < 2, left, right: !left, pause: false, quit: false }
}
