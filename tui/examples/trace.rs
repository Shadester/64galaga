//! Runs the rules with scripted input and prints the whole game state after every tick, for tests/test_lockstep.py.
//! The script and the line format are those of ../thumby/tests/c_trace.c (the C reference).
//! Usage: trace TICKS [START_STAGE] [FORCECAPTURE 0|1] [GODMODE 0|1]
use galaga_tui::game::*;

fn script(g: &Game, t: i32, force_capture: bool) -> Input {
    let mut inp = Input { fire: (t % 7) < 2, left: (t / 90) % 2 != 0, ..Default::default() };
    inp.right = !inp.left;
    if force_capture {
        if g.state == S_PLAY || g.state == S_RESULT {
            inp.fire = false;
        }
        if g.cap == C_BEAM || g.cap == C_CARRY || g.cap == C_DIVING {
            let bx = g.al[g.cap_boss as usize].x;
            inp.left = g.px > bx + 2;
            inp.right = g.px < bx - 2;
            if g.cap == C_CARRY {
                inp.fire = (t & 3) < 2;
            }
        }
    }
    if t % 1500 == 1499 || t % 1500 == 1503 {
        inp.pause = true; // pause, and the next press resumes
    }
    inp
}

fn main() {
    let a: Vec<i32> = std::env::args().skip(1).map(|s| s.parse().unwrap()).collect();
    let ticks = a.first().copied().unwrap_or(3000);
    let start_stage = a.get(1).copied().unwrap_or(0);
    let force_capture = a.get(2).copied().unwrap_or(0) != 0;
    let god = a.get(3).copied().unwrap_or(0) != 0;
    let mut g = Game::new(0);
    let mut out = String::new();
    for t in 0..ticks {
        let inp = script(&g, t, force_capture);
        if god {
            // the ship cannot be hit, except while a tractor beam is on (and then no bomb falls): long games, captures
            g.invuln = if g.cap == C_BEAM || g.cap == C_PULL { 0 } else { 100 };
            if g.cap == C_BEAM {
                g.eb = [Bullet::default(); EBN];
            }
        }
        g.tick(&inp, start_stage);
        let h = [
            g.state, g.paused, g.state_timer, g.frame, g.score, g.hi, g.lives, g.stage, g.diff, g.next_bonus, g.challenge, g.chal_val,
            g.chal_hits, g.chal_timer, g.shots, g.hits, g.px, g.py, g.invuln, g.dual, g.dying_quiet, g.form_dx, g.form_dir, g.form_timer,
            g.entering, g.cap, g.cap_boss, g.beam_len, g.beam_acc, g.beam_timer, g.rx, g.ry, g.snd,
        ];
        out.push_str(&h.iter().map(|v| v.to_string()).collect::<Vec<_>>().join(" "));
        for a in g.al.iter() {
            out.push_str(&format!(" {},{},{},{},{},{},{},{},{},{},{}", a.st, a.x, a.y, a.hp, a.timer, a.dir, a.esc, a.capdive, a.pstep, a.ent, a.dly));
        }
        for b in g.ps.iter() {
            out.push_str(&format!(" {},{},{}", b.x, b.y, b.act));
        }
        for b in g.eb.iter().take(3) {
            out.push_str(&format!(" {},{},{},{}", b.x, b.y, b.act, b.dx));
        }
        // the fields of the arcade rules, after the ones above
        out.push_str(&format!(
            " A {},{},{},{},{},{},{},{},{},{},{},{},{},{},{},{},{}",
            g.fclk, g.ff, g.sway_pos, g.sway_dir, g.breathe, g.bstep, g.clk, g.af, g.tmr2, g.hold, g.sortie[0], g.sortie[1], g.sortie[2],
            g.wingm, g.bomb_flags, g.beam_ph, g.beam_step
        ));
        for a in g.al.iter() {
            out.push_str(&format!(" {},{},{}", a.dpath, a.bflags, a.btmr));
        }
        for b in g.eb.iter() {
            out.push_str(&format!(" {},{},{},{},{}", b.x, b.y, b.act, b.dx, b.ax));
        }
        out.push('\n');
        g.snd = 0;
        g.save_req = 0;
    }
    print!("{}", out);
}
