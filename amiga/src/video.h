/* The screen: three bitmaps of 5 interleaved bitplanes (32 colours), drawn with the blitter while another one is shown. */
#ifndef VIDEO_H
#define VIDEO_H
typedef unsigned char u8;
typedef unsigned short u16;
typedef signed short s16;
typedef unsigned long u32;

#define SCREEN_W 320
#define SCREEN_H 256
#define TOP 28                  /* the play area starts at this line, the hud is above it */

void video_init(void);
void video_begin(void);                              /* the next frame: clear what the frame before drew in this bitmap */
void video_end(int title);                           /* show it (at the next vertical blank), with the title or the game palette */
void video_title(int on);                            /* the title picture on or off in the bitmap (call it in every frame) */
typedef struct { s16 id, x, y; } Obj;                 /* a sprite in a slot (id -1: nothing) */
extern Obj want[];
/* sprite id (assets.h) with its top left at x, y (may be partly outside), in a slot (0..41): the same sprite in the same slot is the
 * same object in the next frame, and it is not drawn again if it did not move */
static inline void video_bob(int slot, int id, int x, int y) { want[slot].id = id; want[slot].x = x; want[slot].y = y; }
void video_static_bob(int id, int x, int y);         /* in the static layer: drawn at once */
#define STAR_ROWS (SCREEN_H - 16 - TOP)                /* the offsets of the layers wrap at this number */
void video_stars(int slow, int fast);                /* hardware sprites: the starfield, scrolled by these two offsets (negative: no stars) */
void video_text(const char *s, int x, int y, int colour);   /* x is rounded down to a multiple of 8 */
void video_beam(int x, int y, int rows, int phase);  /* the tractor beam: rows of 8 pixel cells, widening, under x, y */
int video_static_begin(int a, int b, int c, int d);   /* 1: draw the hud (text, lives) now, then call video_static_end() */
void video_static_end(void);
void video_wait_blitter(void);
#endif
