//! Galaga for the terminal and the browser. The rules (`game`) are a translation of psp/game.c; `render` makes the frame of cells.
//! The terminal front end (`input`, `term`, `hiscore`, and the program in main.rs) needs the feature `terminal`; the browser front end (`web`)
//! is the WebAssembly module of docs/tui.
pub mod arcade_data;
pub mod art;
pub mod game;
pub mod render;
#[cfg(feature = "terminal")]
pub mod hiscore;
#[cfg(feature = "terminal")]
pub mod input;
#[cfg(feature = "terminal")]
pub mod term;
pub mod web;
