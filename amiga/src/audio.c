#include "audio.h"
#include "game.h"
#include "assets.h"

typedef unsigned char u8;
typedef unsigned short u16;
typedef unsigned long u32;
#define CUSTOM ((volatile u16 *)0xdff000)
#define W(reg) (CUSTOM[(reg) / 2])
#define AUD(ch, off) W(0x0a0 + (ch) * 0x10 + (off))        /* off: 0 LCH, 2 LCL, 4 LEN, 6 PER, 8 VOL */
#define DMACON W(0x096)

static const u16 silence[2] = {0, 0};
static const signed char wave[16] __attribute__((aligned(2))) = {70, 70, 70, 70, 70, 70, 70, 70, -70, -70, -70, -70, -70, -70, -70, -70};
static int jn, jn_left, jn_ticks;                         /* the jingle: the next note, notes left, ticks of the note */

static void set_ptr(int ch, const void *p, int words) {
    AUD(ch, 0) = (u32)p >> 16;
    AUD(ch, 2) = (u32)p & 0xffff;
    AUD(ch, 4) = words;
}

static void wait_line(void) {
    u16 v = W(0x006) >> 8;
    while ((W(0x006) >> 8) == v) ;
}

/* A sample that plays once: Paula repeats what it has, so after it started, the pointer is set to a silent word. */
static void sfx(int ch, int id, int vol) {
    DMACON = 1 << ch;
    set_ptr(ch, sfx_data + sfx_table[id][0], sfx_table[id][1]);
    AUD(ch, 6) = SFX_RATE_PERIOD;
    AUD(ch, 8) = vol;
    DMACON = 0x8000 | (1 << ch);
    wait_line();
    set_ptr(ch, silence, 1);
}

static void note(void) {
    const u16 *n = jingle_notes[jn];
    jn_ticks = n[1];
    if (n[0]) { AUD(2, 6) = n[0]; AUD(2, 8) = 56; }
    else AUD(2, 8) = 0;
    ++jn;
    --jn_left;
}

static void jingle(int k) {
    DMACON = 4;
    set_ptr(2, wave, 8);
    jn = jingle_table[k][0];
    jn_left = jingle_table[k][1];
    note();
    DMACON = 0x8004;
}

void audio_init(void) {
    DMACON = 0x000f;
    jn_left = jn_ticks = 0;
}

void audio_mute(void) {
    DMACON = 0x000f;
    jn_left = jn_ticks = 0;
}

void audio_play(int snd) {
    int k;
    if (snd & SND_SHOOT) sfx(0, SFX_SHOOT, 36);
    if (snd & SND_HIT) sfx(0, SFX_HIT, 56);
    if (snd & SND_EXPLODE) sfx(1, SFX_EXPLOSION, 56);
    if (snd & SND_DEATH) sfx(1, SFX_DEATH, 64);
    if (snd & SND_SWOOP) sfx(3, SFX_SWOOP, 30);
    for (k = 0; k < 5; ++k)
        if (snd & (JG_STAGE << k)) jingle(k);
}

void audio_tick(void) {
    if (!jn_ticks) return;
    if (--jn_ticks == 1 && jn_left) AUD(2, 8) = 0;           /* the last tick of a note is silent: the notes are separate */
    if (jn_ticks) return;
    if (jn_left) note();
    else DMACON = 4;                                         /* the jingle is over */
}
