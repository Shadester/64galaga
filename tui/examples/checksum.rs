//! Prints the checksum of the game after N autoplay ticks with the ship invulnerable, through the same exports the browser uses:
//! tests/test_web.py compares it with the one from the WebAssembly module. Usage: checksum [TICKS]
use galaga_tui::web::*;

fn main() {
    let n: u32 = std::env::args().nth(1).and_then(|s| s.parse().ok()).unwrap_or(4000);
    web_init(0, 0, 1, 1, 137, 40);
    for _ in 0..n {
        web_tick(0);
    }
    println!("{}", web_checksum());
}
