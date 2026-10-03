//! Galaga for the terminal. Keys: A / D or the arrows move, Space fires, P pauses, Q quits (on the title screen: leaves).
use crossterm::event::{self, Event};
use galaga_tui::game::*;
use galaga_tui::hiscore;
use galaga_tui::input::Keys;
use galaga_tui::render::{layout, Renderer};
use galaga_tui::term::Term;
use std::io;
use std::time::{Duration, Instant};

const TICK: Duration = Duration::from_millis(1000 / TICK_HZ);
const FRAME: Duration = Duration::from_millis(33);

const HELP: &str = "Galaga for the terminal
Keys: A / D or the arrows move, Space fires, P pauses, Q quits (on the title screen: leaves the program).
Options: --autoplay (the ship plays itself), --stage N (start at stage N), --god (the ship cannot be hit),
         --no-save (do not write the hi-score file), --help";

fn main() -> io::Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.iter().any(|a| a == "--help" || a == "-h") {
        println!("{}", HELP);
        return Ok(());
    }
    let autoplay = args.iter().any(|a| a == "--autoplay");
    let god = args.iter().any(|a| a == "--god");
    let save = !args.iter().any(|a| a == "--no-save");
    let start_stage = args.iter().position(|a| a == "--stage").and_then(|i| args.get(i + 1)).and_then(|v| v.parse().ok()).unwrap_or(0);
    let mut term = Term::new()?;
    let mut game = Game::new(if save { hiscore::load() } else { 0 });
    let now = Instant::now();
    let mut keys = Keys::new(term.enhanced, now);
    let (mut cols, mut rows) = term.size();
    let mut renderer = layout(cols, rows).map(Renderer::new);
    let mut next_tick = now;
    let mut last_draw = now - FRAME;
    let mut dirty = true;
    loop {
        // wait for the next event or tick
        let now = Instant::now();
        let wait = next_tick.saturating_duration_since(now).min(FRAME);
        if event::poll(wait)? {
            let ev = event::read()?;
            if let Event::Resize(c, r) = ev {
                cols = c as usize;
                rows = r as usize;
                renderer = layout(cols, rows).map(Renderer::new);
                term.invalidate();
                dirty = true;
            }
            keys.event(ev, Instant::now());
            while event::poll(Duration::ZERO)? {
                keys.event(event::read()?, Instant::now());
            }
        }
        if keys.exit || (game.state == S_TITLE && keys.peek_quit()) {
            break;
        }
        let now = Instant::now();
        let mut ticks = 0;
        while now >= next_tick && ticks < 5 {
            let typed = keys.take(now);
            let inp = if autoplay { Input { pause: typed.pause, quit: typed.quit, ..game_autoplay(&game) } } else { typed };
            if god {
                game.invuln = 100;
            }
            game.tick(&inp, start_stage);
            if save && game.save_req != 0 {
                hiscore::save(game.hi);
            }
            game.snd = 0;
            game.save_req = 0;
            next_tick += TICK;
            ticks += 1;
            dirty = true;
        }
        if now >= next_tick + TICK * 5 {
            next_tick = now; // far behind (the program was stopped): do not run to catch up
        }
        if dirty && now.duration_since(last_draw) >= FRAME {
            match renderer.as_mut() {
                Some(r) => term.present(r.draw(&game, cols, rows))?,
                None => term.present(galaga_tui::render::too_small(cols, rows))?,
            }
            last_draw = now;
            dirty = false;
        }
    }
    if save {
        hiscore::save(game.hi);
    }
    Ok(())
}
