/* Pixel art: 16 rows of 8 chars (left half, mirrored to 16x16).
 * . clear | m main, M light, n dark (per-variant) | y yellow, Y dark yellow, c cyan, w white,
 * k near-black, o orange, r red, b blue, g grey */
#ifndef ART_H
#define ART_H

#define ART_ROWS 16
typedef const char *const ArtRows[ART_ROWS];

/* Bee (zako): blue. Frame A wings up, frame B wings down. */
static ArtRows art_bee_a = {
    "........", "...y....", "....y...", ".n...mmm", "nMn.mMMm", "nMMnmmMm", "nMMnmkkm", ".nMmmmmm",
    "..nmmYyy", "...nmmmm", "....mYyy", "....nmmm", ".....nmm", "......nn", "........", "........" };
static ArtRows art_bee_b = {
    "........", "...y....", "....y...", ".....mmm", "....mMMm", "...nmmMm", "...nmkkm", ".n.nmmmm",
    "nMn.mYyy", "nMMnmmmm", "nMMnmYyy", ".nMmnmmm", "..nmnnmm", "...n.nnn", "........", "........" };

/* Butterfly (goei): red. Frame A wings open, frame B closed. */
static ArtRows art_bfly_a = {
    "........", "..y...y.", "...y.y..", "Mm....cc", "MMmn..cw", "MMMmn.cc", "mMMmnmcc", ".mmmmmmm",
    ".nmmmmym", "..nmmmmm", "..nnmmmM", "...nmmMm", "....nmmm", ".....nnm", "........", "........" };
static ArtRows art_bfly_b = {
    "........", "...y.y..", "....yy..", ".....ccc", "....mcww", "....mmcc", "...mMmcc", "...mMmmm",
    "...nMmmy", "....mmmm", "....nmmm", "...mnmMm", "...mnnmm", "....nmnn", "........", "........" };

/* Boss Galaga: green (purple when damaged). Frame A legs splayed, B legs tucked. */
static ArtRows art_boss_a = {
    "........", "...c..cc", "..ccy.cc", "...cyyyc", "..mmmmmc", ".mMMmmmm", ".mMYymmY", "nmmYyYmm",
    "nnmmmmmm", "..nMmmmm", "..nnmmmm", ".nmn.mmm", "nm.n.nmm", "n..n..nn", "........", "........" };
static ArtRows art_boss_b = {
    "........", "...c..cc", "..ccy.cc", "...cyyyc", "..mmmmmc", ".mMMmmmm", ".mMYymmY", "nmmYyYmm",
    "nnmmmmmm", "..nMmmmm", "..nnmmmm", "..nnmmmm", "...nmnmm", "...nn.nn", "........", "........" };

/* Player fighter. */
static ArtRows art_player = {
    ".......w", ".......w", ".......w", "......ww", "......wr", "......wr", ".....bww", ".....bwc",
    "..r..bww", "..rb.bbw", "..rbbbbb", ".wrbbbwb", ".wbbbbwb", ".wb..bbk", ".rr...rr", "........" };

/* Explosions: alien 3 frames (palette o/y/c/w), player 4 frames. */
static ArtRows art_xa0 = {
    "........", "........", "........", "........", "........", ".......o", "......oy", ".....oyw",
    ".....oyw", "......oy", ".......o", "........", "........", "........", "........", "........" };
static ArtRows art_xa1 = {
    "........", "........", "...o....", "....o..y", ".....o..", "..y..ow.", "......yw", "..oo.ywy",
    "..oo.ywy", "......yw", "..y..ow.", ".....o..", "....o..y", "...o....", "........", "........" };
static ArtRows art_xa2 = {
    "........", ".y....o.", "........", "...y....", "o....y..", "........", "..o...y.", "y.......",
    "y.....o.", "..o...y.", "........", "o....y..", "...y....", "........", ".y....o.", "........" };
static ArtRows art_xp0 = {
    "........", "........", "........", "........", "........", "........", ".......w", "......wy",
    "......wy", ".......w", "........", "........", "........", "........", "........", "........" };
static ArtRows art_xp1 = {
    "........", "........", "........", "......y.", ".....ww.", "....wyyw", "...wyycw", "...wycww",
    "...wycww", "...wyyyw", "....wyww", ".....ww.", "......y.", "........", "........", "........" };
static ArtRows art_xp2 = {
    "........", "..y.....", "...w..c.", "....wy..", "..c.ywy.", ".w.ywcyw", "..ywcyyw", ".yycwywc",
    ".yycwywc", "..ywcyyw", ".w.ywcyw", "..c.ywy.", "....wy..", "...w..c.", "..y.....", "........" };
static ArtRows art_xp3 = {
    "y......w", "..w.....", "....c..y", ".y......", "......w.", "c...y...", "..w....y", "........",
    "........", "y.....w.", "...y....", ".w.....c", "......y.", "y...w...", "...c....", "w......y" };

#endif
