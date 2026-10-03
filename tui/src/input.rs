//! Keys to the input of the game. A terminal sends key presses, and key releases only when it supports the kitty keyboard protocol
//! (`enhanced`): then a key is held from its press to its release. Without it a key is held for a short time after its last press or
//! repeat (the ship keeps going while the key repeats). Fire is one shot for each press or repeat.
use crate::game::Input;
use crossterm::event::{Event, KeyCode, KeyEvent, KeyEventKind, KeyModifiers};
use std::time::{Duration, Instant};

/// How long a key counts as held after a press that is not a repeat (the repeat of a key starts after about half a second), and after a repeat.
const HOLD_FIRST: Duration = Duration::from_millis(250);
const HOLD_REPEAT: Duration = Duration::from_millis(110);
/// Two presses of a key this close are a repeat.
const REPEAT_GAP: Duration = Duration::from_millis(140);

#[derive(Clone, Copy)]
struct Held {
    down: bool,
    until: Instant,
    last: Instant,
}

impl Held {
    fn new(now: Instant) -> Held {
        Held { down: false, until: now, last: now - Duration::from_secs(10) }
    }
    fn press(&mut self, now: Instant, enhanced: bool, kind: KeyEventKind) {
        if enhanced {
            self.down = kind != KeyEventKind::Release;
        } else {
            self.until = now + if now - self.last < REPEAT_GAP { HOLD_REPEAT } else { HOLD_FIRST };
        }
        self.last = now;
    }
    fn release(&mut self, now: Instant) {
        self.down = false;
        self.until = now;
    }
    fn held(&self, now: Instant, enhanced: bool) -> bool {
        if enhanced { self.down } else { now < self.until }
    }
}

pub struct Keys {
    pub enhanced: bool,
    left: Held,
    right: Held,
    fire: bool,
    pause: bool,
    quit: bool,
    pub exit: bool,
    pub resized: bool,
}

impl Keys {
    pub fn new(enhanced: bool, now: Instant) -> Keys {
        Keys { enhanced, left: Held::new(now), right: Held::new(now), fire: false, pause: false, quit: false, exit: false, resized: false }
    }

    pub fn event(&mut self, ev: Event, now: Instant) {
        match ev {
            Event::Resize(..) => self.resized = true,
            Event::Key(KeyEvent { code, modifiers, kind, .. }) => self.key(code, modifiers, kind, now),
            _ => {}
        }
    }

    fn key(&mut self, code: KeyCode, mods: KeyModifiers, kind: KeyEventKind, now: Instant) {
        if mods.contains(KeyModifiers::CONTROL) && code == KeyCode::Char('c') {
            self.exit = true;
            return;
        }
        let release = kind == KeyEventKind::Release;
        match code {
            KeyCode::Left | KeyCode::Char('a') | KeyCode::Char('A') => {
                self.left.press(now, self.enhanced, kind);
                if !release {
                    self.right.release(now);
                }
            }
            KeyCode::Right | KeyCode::Char('d') | KeyCode::Char('D') => {
                self.right.press(now, self.enhanced, kind);
                if !release {
                    self.left.release(now);
                }
            }
            KeyCode::Char(' ') | KeyCode::Char('k') | KeyCode::Char('K') | KeyCode::Enter | KeyCode::Up => self.fire |= !release,
            KeyCode::Char('p') | KeyCode::Char('P') if !release && kind == KeyEventKind::Press => self.pause = true,
            KeyCode::Char('q') | KeyCode::Char('Q') | KeyCode::Esc if !release => self.quit = true,
            _ => {}
        }
    }

    /// The input for the next tick (the pulses are used up).
    pub fn take(&mut self, now: Instant) -> Input {
        let inp = Input {
            left: self.left.held(now, self.enhanced),
            right: self.right.held(now, self.enhanced),
            fire: self.fire,
            pause: self.pause,
            quit: self.quit,
        };
        self.fire = false;
        self.pause = false;
        self.quit = false;
        inp
    }

    /// Q was pressed (to leave the program from the title screen); asks and clears.
    pub fn peek_quit(&self) -> bool {
        self.quit
    }
}
