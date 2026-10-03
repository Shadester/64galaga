/* PSP Galaga: platform layer (GU renderer, audio synth, input, hi-score file).
 * All rules live in game.c; this file only draws and plays what the game reports. */
#include <pspkernel.h>
#include <pspctrl.h>
#include <pspdisplay.h>
#include <pspgu.h>
#include <pspiofilemgr.h>
#include <pspaudio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <stdio.h>
#include "game.h"
#include "art.h"
#include "logo.h"

PSP_MODULE_INFO("PSP Galaga", 0, 1, 0);
PSP_MAIN_THREAD_ATTR(THREAD_ATTR_USER | THREAD_ATTR_VFPU);
PSP_HEAP_SIZE_KB(-1024);

#define SCREEN_W 480
#define SCREEN_H 272
#define BUF_W 512
#define RGBA(r, g, b, a) ((unsigned)(r) | ((unsigned)(g) << 8) | ((unsigned)(b) << 16) | ((unsigned)(a) << 24))
#define RGB(r, g, b) RGBA(r, g, b, 255)
#ifndef TITLE_HOLD
#define TITLE_HOLD 150   /* AUTOPLAY: frames the title screen stays before autoplay presses fire */
#endif
#ifndef SHOT_FROM
#define SHOT_FROM 60
#endif
#ifndef SHOT_EVERY
#define SHOT_EVERY 60
#endif
#ifndef SHOT_MAX
#define SHOT_MAX 60
#endif
#define SAVE_DIR "ms0:/PSP/SAVEDATA/PSPGALAGA"
#define SCORE_FILE SAVE_DIR "/HISCORE.DAT"

extern unsigned char msx[];   /* 8x8 font from libpspdebug */

static unsigned int __attribute__((aligned(16))) guList[262144];
static Game g, prev;
static int running = 1, savedHi;
static float ia;              /* interpolation between the previous and current 50 Hz tick */
static float starTime;

/* ------------------------------------------------------------------ audio */
/* Three SID-like voices mixed in their own thread. The game only queues events. */
#define SR 44100
#define TICK_SAMPLES (SR / TICK_HZ)
typedef struct { const short *n; } Jingle;
typedef struct { int wave; float ph, freq, amp, dec, noiseRate, noiseAcc, noiseVal; unsigned lfsr; } Voice;
static volatile unsigned evq[32];
static volatile int evHead, evTail, audioMute;
static Voice vc[3];
static int swoopTicks, jTicks, jIdx;
static const short *jNotes;    /* pairs: frequency in Hz, duration in ticks */
static const short jStage[]   = {392,7, 523,7, 659,7, 784,7, 1047,30, 0};
static const short jOver[]    = {523,12, 440,12, 349,12, 262,40, 0};
static const short jCapture[] = {523,6, 440,6, 349,6, 294,6, 262,20, 0};
static const short jRescue[]  = {523,5, 659,5, 784,5, 1047,5, 784,5, 1047,20, 0};
static const short jBonus[]   = {784,4, 1047,4, 784,4, 1047,4, 784,4, 1047,16, 0};

static void queueSound(unsigned e) { evq[evHead & 31] = e; ++evHead; }
static void voiceOn(Voice *v, int wave, float freq, float amp, float tau) {
    v->wave = wave; v->freq = freq; v->amp = amp; v->dec = expf(-1.0f / (tau * SR));
    v->noiseRate = freq; v->lfsr = 0x7ffff8; v->noiseAcc = 0;
}
static void startJingle(const short *notes) {
    jNotes = notes; jIdx = 0; jTicks = 0; swoopTicks = 0;
    vc[2].wave = 2; vc[2].dec = 1.0f;
}
static void handleEvent(unsigned e) {
    if (e & SND_SHOOT) voiceOn(&vc[0], 0, 1200, .35f, .09f);
    if (e & SND_HIT) voiceOn(&vc[0], 1, 360, .3f, .28f);
    if (e & SND_EXPLODE) voiceOn(&vc[1], 3, 481, .5f, .3f);
    if (e & SND_DEATH) voiceOn(&vc[1], 3, 180, .65f, .8f);
    if ((e & SND_SWOOP) && !jNotes) { swoopTicks = 23; vc[2].wave = 1; vc[2].dec = 1.0f; vc[2].amp = .22f; }
    if (e & JG_STAGE) startJingle(jStage);
    if (e & JG_OVER) startJingle(jOver);
    if (e & JG_CAPTURE) startJingle(jCapture);
    if (e & JG_RESCUE) startJingle(jRescue);
    if (e & JG_BONUS) startJingle(jBonus);
}
static void audioTick(void) {
    Voice *v = &vc[2];
    if (jNotes) {
        if (jNotes[jIdx * 2] == 0) { jNotes = NULL; v->amp = 0; return; }
        if (jTicks == 0) { v->freq = jNotes[jIdx * 2]; v->amp = .2f; v->wave = 2; }
        else v->amp = .13f + .07f * expf(-jTicks * .2f);
        if (++jTicks > jNotes[jIdx * 2 + 1]) { jTicks = 0; ++jIdx; }
    } else if (swoopTicks > 0) {
        v->freq = (swoopTicks * 2 + 8) * 15.03f; --swoopTicks;
        if (!swoopTicks) v->amp = 0;
    }
}
static short audioBuf[2][512 * 2] __attribute__((aligned(64)));
static int audioThread(SceSize a, void *b) {
    int ch = sceAudioChReserve(PSP_AUDIO_NEXT_CHANNEL, 512, PSP_AUDIO_FORMAT_STEREO), cur = 0, tickCount = 0, i, k;
    (void)a; (void)b;
    if (ch < 0) return 0;
    while (running) {
        short *out = audioBuf[cur ^= 1];
        while (evTail != evHead) { handleEvent(evq[evTail & 31]); ++evTail; }
        for (i = 0; i < 512; ++i) {
            float mix = 0;
            if (++tickCount >= TICK_SAMPLES) { tickCount = 0; audioTick(); }
            for (k = 0; k < 3; ++k) {
                Voice *v = &vc[k];
                float s = 0, step;
                if (v->amp < .0005f) continue;
                if (v->wave == 3) {
                    v->noiseAcc += v->noiseRate / SR;
                    while (v->noiseAcc >= 1.0f) {
                        unsigned bit = ((v->lfsr >> 22) ^ (v->lfsr >> 17)) & 1;
                        v->lfsr = ((v->lfsr << 1) | bit) & 0x7fffff;
                        v->noiseVal = ((v->lfsr >> 10) & 0xff) / 127.5f - 1.0f; v->noiseAcc -= 1.0f;
                    }
                    s = v->noiseVal;
                } else {
                    step = v->freq / SR; v->ph += step; if (v->ph >= 1.0f) v->ph -= 1.0f;
                    s = v->wave == 0 ? (v->ph < .5f ? 4 * v->ph - 1 : 3 - 4 * v->ph)
                      : v->wave == 1 ? 2 * v->ph - 1 : (v->ph < .5f ? 1.0f : -1.0f);
                }
                mix += s * v->amp; v->amp *= v->dec;
            }
            if (audioMute) mix = 0;
            if (mix > 1) mix = 1;
            if (mix < -1) mix = -1;
            out[i * 2] = out[i * 2 + 1] = (short)(mix * 20000);
        }
        sceAudioOutputBlocking(ch, PSP_AUDIO_VOLUME_MAX, out);
    }
    sceAudioChRelease(ch);
    return 0;
}

/* ------------------------------------------------------------- hi-score */
static void loadHighScore(void) {
    SceUID f = sceIoOpen(SCORE_FILE, PSP_O_RDONLY, 0);
    if (f >= 0) { sceIoRead(f, &savedHi, sizeof savedHi); sceIoClose(f); }
}
static void saveHighScore(void) {
    SceUID f;
    sceIoMkdir("ms0:/PSP", 0777); sceIoMkdir("ms0:/PSP/SAVEDATA", 0777); sceIoMkdir(SAVE_DIR, 0777);
    f = sceIoOpen(SCORE_FILE, PSP_O_WRONLY | PSP_O_CREAT | PSP_O_TRUNC, 0666);
    if (f >= 0) { sceIoWrite(f, &g.hi, sizeof g.hi); sceIoClose(f); savedHi = g.hi; }
}

/* -------------------------------------------------------------- textures */
enum { X_BEE = 0, X_BFLY = 2, X_BOSS = 4, X_BOSSP = 6, X_PLAYER = 8, X_XA = 9, X_XP = 12 };
static unsigned int __attribute__((aligned(16))) atlas[256 * 64];   /* 16x16 cells, glow at (0,16) */
static unsigned int __attribute__((aligned(16))) fontTex[128 * 64]; /* ASCII 32..127, 8x8 */
static unsigned int __attribute__((aligned(16))) logoTex[LOGO_W * LOGO_H];

static const unsigned char vbee[3][3] = {{70,130,255},{150,200,255},{30,60,190}};
static const unsigned char vbfly[3][3] = {{255,60,60},{255,150,130},{160,20,40}};
static const unsigned char vboss[3][3] = {{60,220,90},{170,255,160},{20,130,50}};
static const unsigned char vbossp[3][3] = {{170,80,255},{215,165,255},{100,40,170}};
static unsigned pixelColor(char ch, const unsigned char (*var)[3]) {
    switch (ch) {
    case 'm': return RGB(var[0][0], var[0][1], var[0][2]);
    case 'M': return RGB(var[1][0], var[1][1], var[1][2]);
    case 'n': return RGB(var[2][0], var[2][1], var[2][2]);
    case 'y': return RGB(255, 220, 60);  case 'Y': return RGB(200, 140, 20);
    case 'c': return RGB(80, 230, 255);  case 'w': return RGB(255, 255, 255);
    case 'k': return RGB(25, 25, 50);    case 'o': return RGB(255, 140, 30);
    case 'r': return RGB(255, 60, 60);   case 'b': return RGB(60, 110, 255);
    case 'g': return RGB(170, 170, 190);
    }
    return 0;
}
static void cell(int idx, ArtRows rows, const unsigned char (*var)[3]) {
    int x, y;
    for (y = 0; y < 16; ++y) for (x = 0; x < 16; ++x)
        atlas[y * 256 + idx * 16 + x] = pixelColor(x < 8 ? rows[y][x] : rows[y][15 - x], var);
}
static void buildTextures(void) {
    int i, x, y;
    cell(X_BEE, art_bee_a, vbee); cell(X_BEE + 1, art_bee_b, vbee);
    cell(X_BFLY, art_bfly_a, vbfly); cell(X_BFLY + 1, art_bfly_b, vbfly);
    cell(X_BOSS, art_boss_a, vboss); cell(X_BOSS + 1, art_boss_b, vboss);
    cell(X_BOSSP, art_boss_a, vbossp); cell(X_BOSSP + 1, art_boss_b, vbossp);
    cell(X_PLAYER, art_player, vbee);
    cell(X_XA, art_xa0, vbee); cell(X_XA + 1, art_xa1, vbee); cell(X_XA + 2, art_xa2, vbee);
    cell(X_XP, art_xp0, vbee); cell(X_XP + 1, art_xp1, vbee); cell(X_XP + 2, art_xp2, vbee); cell(X_XP + 3, art_xp3, vbee);
    for (y = 0; y < 32; ++y) for (x = 0; x < 32; ++x) {   /* soft radial glow */
        float dx = (x - 15.5f) / 16, dy = (y - 15.5f) / 16, d = 1 - sqrtf(dx * dx + dy * dy);
        int a = d <= 0 ? 0 : (int)(255 * d * d);
        atlas[(16 + y) * 256 + x] = RGBA(255, 255, 255, a);
    }
    for (i = 0; i < 96; ++i) for (y = 0; y < 8; ++y) for (x = 0; x < 8; ++x)
        fontTex[((i / 16) * 8 + y) * 128 + (i % 16) * 8 + x] = (msx[(i + 32) * 8 + y] & (0x80 >> x)) ? 0xffffffffu : 0;
    memcpy(logoTex, logo_px, sizeof logoTex);
    sceKernelDcacheWritebackAll();
}

/* --------------------------------------------------------------- drawing */
typedef struct { short u, v, x, y, z; } TVert;
typedef struct { unsigned color; short x, y, z; } CVert;
enum { TX_NONE, TX_ATLAS, TX_FONT, TX_LOGO };
static int curTex;
static void useTex(int t) {
    if (t == curTex) return;
    curTex = t;
    if (t == TX_NONE) { sceGuDisable(GU_TEXTURE_2D); return; }
    sceGuEnable(GU_TEXTURE_2D);
    if (t == TX_ATLAS) sceGuTexImage(0, 256, 64, 256, atlas);
    else if (t == TX_FONT) sceGuTexImage(0, 128, 64, 128, fontTex);
    else sceGuTexImage(0, LOGO_W, LOGO_H, LOGO_W, logoTex);
}
static void blendNormal(void) { sceGuBlendFunc(GU_ADD, GU_SRC_ALPHA, GU_ONE_MINUS_SRC_ALPHA, 0, 0); }
static void blendAdd(void) { sceGuBlendFunc(GU_ADD, GU_SRC_ALPHA, GU_FIX, 0, 0xffffffff); }

static void rect(float x, float y, float w, float h, unsigned color) {
    CVert *v;
    useTex(TX_NONE);
    v = sceGuGetMemory(2 * sizeof *v);
    v[0].color = v[1].color = color;
    v[0].x = (short)x; v[0].y = (short)y; v[0].z = 0;
    v[1].x = (short)(x + w + .5f); v[1].y = (short)(y + h + .5f); v[1].z = 0;
    sceGuDrawArray(GU_SPRITES, GU_COLOR_8888 | GU_VERTEX_16BIT | GU_TRANSFORM_2D, 2, NULL, v);
}
/* Vertical gradient quad (top colour to bottom colour). */
static void vgrad(float x, float y, float w, float h, unsigned top, unsigned bot) {
    CVert *v;
    useTex(TX_NONE);
    v = sceGuGetMemory(4 * sizeof *v);
    v[0].color = v[1].color = top; v[2].color = v[3].color = bot;
    v[0].x = v[2].x = (short)x; v[1].x = v[3].x = (short)(x + w);
    v[0].y = v[1].y = (short)y; v[2].y = v[3].y = (short)(y + h);
    v[0].z = v[1].z = v[2].z = v[3].z = 0;
    sceGuDrawArray(GU_TRIANGLE_STRIP, GU_COLOR_8888 | GU_VERTEX_16BIT | GU_TRANSFORM_2D, 4, NULL, v);
}
/* Horizontal trapezoid, full colour at both edges, for the tractor beam. */
static void trap(float cx, float y0, float hw0, float y1, float hw1, unsigned c0, unsigned c1) {
    CVert *v;
    useTex(TX_NONE);
    v = sceGuGetMemory(4 * sizeof *v);
    v[0].color = v[1].color = c0; v[2].color = v[3].color = c1;
    v[0].x = (short)(cx - hw0); v[1].x = (short)(cx + hw0); v[2].x = (short)(cx - hw1); v[3].x = (short)(cx + hw1);
    v[0].y = v[1].y = (short)y0; v[2].y = v[3].y = (short)y1;
    v[0].z = v[1].z = v[2].z = v[3].z = 0;
    sceGuDrawArray(GU_TRIANGLE_STRIP, GU_COLOR_8888 | GU_VERTEX_16BIT | GU_TRANSFORM_2D, 4, NULL, v);
}
/* Atlas cell centred at (cx, cy), drawn size x size. */
static void spr(int idx, float cx, float cy, float size, unsigned tint) {
    TVert *v;
    useTex(TX_ATLAS);
    v = sceGuGetMemory(2 * sizeof *v);
    sceGuColor(tint);
    v[0].u = idx * 16; v[0].v = 0; v[1].u = idx * 16 + 16; v[1].v = 16;
    v[0].x = (short)(cx - size / 2); v[0].y = (short)(cy - size / 2);
    v[1].x = (short)(cx + size / 2); v[1].y = (short)(cy + size / 2);
    v[0].z = v[1].z = 0;
    sceGuDrawArray(GU_SPRITES, GU_TEXTURE_16BIT | GU_VERTEX_16BIT | GU_TRANSFORM_2D, 2, NULL, v);
}
static void glow(float cx, float cy, float size, unsigned tint) {
    TVert *v;
    useTex(TX_ATLAS);
    v = sceGuGetMemory(2 * sizeof *v);
    sceGuColor(tint);
    v[0].u = 0; v[0].v = 16; v[1].u = 32; v[1].v = 48;
    v[0].x = (short)(cx - size / 2); v[0].y = (short)(cy - size / 2);
    v[1].x = (short)(cx + size / 2); v[1].y = (short)(cy + size / 2);
    v[0].z = v[1].z = 0;
    sceGuDrawArray(GU_SPRITES, GU_TEXTURE_16BIT | GU_VERTEX_16BIT | GU_TRANSFORM_2D, 2, NULL, v);
}
static int textW(const char *s, int scale) { return (int)strlen(s) * 8 * scale; }
static void textRaw(int x, int y, int scale, const char *s, unsigned color) {
    int n = (int)strlen(s), i, k = 0;
    TVert *v;
    if (!n) return;
    useTex(TX_FONT);
    v = sceGuGetMemory(2 * n * sizeof *v);
    sceGuColor(color);
    for (i = 0; i < n; ++i, x += 8 * scale) {
        int c = (unsigned char)s[i] - 32;
        if (c < 0 || c > 95 || c == 0) continue;
        v[k].u = (c % 16) * 8; v[k].v = (c / 16) * 8; v[k + 1].u = v[k].u + 8; v[k + 1].v = v[k].v + 8;
        v[k].x = x; v[k].y = y; v[k + 1].x = x + 8 * scale; v[k + 1].y = y + 8 * scale;
        v[k].z = v[k + 1].z = 0; k += 2;
    }
    if (k) sceGuDrawArray(GU_SPRITES, GU_TEXTURE_16BIT | GU_VERTEX_16BIT | GU_TRANSFORM_2D, k, NULL, v);
}
static void text(int x, int y, int scale, const char *s, unsigned color) {
    textRaw(x + (scale > 1 ? 2 : 1), y + (scale > 1 ? 2 : 1), scale, s, RGBA(0, 0, 40, 200));
    textRaw(x, y, scale, s, color);
}
static void ctext(int y, int scale, const char *s, unsigned color) { text((SCREEN_W - textW(s, scale)) / 2, y, scale, s, color); }

/* C64 sprite coordinates to screen. The 320x200 play area is scaled by 1.36 to 435x272. */
static float fx(float x) { return 22.5f + (x - 24) * 1.36f; }
static float fy(float y) { return 20 + (y - 50) * 1.27f; }
static float lerpi(int a, int b) { return abs(b - a) > 40 ? (float)b : a + (b - a) * ia; }

/* ------------------------------------------------------------- particles */
typedef struct { float x, y, vx, vy, life, max; unsigned rgb; } Part;
static Part parts[192];
static void burst(float x, float y, int n, float speed, const unsigned *pal, int np) {
    int i, k;
    for (i = 0; i < n; ++i) for (k = 0; k < 192; ++k) if (parts[k].life <= 0) {
        float a = (rand() & 1023) * 6.2831853f / 1024, s = speed * (.3f + (rand() & 255) / 255.0f);
        parts[k].x = x; parts[k].y = y; parts[k].vx = cosf(a) * s; parts[k].vy = sinf(a) * s;
        parts[k].max = parts[k].life = .35f + (rand() & 255) / 255.0f * .5f; parts[k].rgb = pal[rand() % np];
        break;
    }
}
static const unsigned palAlien[] = {RGB(255,140,30), RGB(255,220,60), RGB(80,230,255), RGB(255,255,255)};
static const unsigned palShip[] = {RGB(255,255,255), RGB(80,230,255), RGB(255,220,60), RGB(255,80,60)};
static void drawParticles(void) {
    int k;
    blendAdd();
    for (k = 0; k < 192; ++k) if (parts[k].life > 0) {
        Part *p = &parts[k];
        float f = p->life / p->max;
        p->x += p->vx; p->y += p->vy; p->vx *= .95f; p->vy *= .95f; p->life -= 1.0f / 60;
        glow(p->x, p->y, 4 + 10 * f, (p->rgb & 0xffffff) | ((unsigned)(200 * f) << 24));
    }
    blendNormal();
}

/* -------------------------------------------------------------- scenes */
static void drawStars(void) {
    static const float speed[4] = {5.4f, 2.7f, 2.7f, 1.8f};
    static const unsigned char bright[4] = {255, 200, 150, 100};
    int i;
    for (i = 0; i < 100; ++i) {
        unsigned h = (unsigned)i * 2654435761u;
        int layer = i < 12 ? 0 : i < 40 ? 1 : i < 70 ? 2 : 3;
        float x = 22 + (h >> 8) % 436, y = fmodf(((h >> 20) % SCREEN_H) + starTime * speed[layer], SCREEN_H);
        float tw = .65f + .35f * sinf(starTime * .12f + i * 1.7f);
        int b = (int)(bright[layer] * tw), sz = layer == 0 ? 2 : 1;
        unsigned col = i % 5 == 0 ? RGB(b, b * 3 / 4, b / 3) : i % 7 == 0 ? RGB(b / 2, b * 3 / 4, b) : RGB(b, b, b);
        rect(x, y, sz, layer == 0 ? 3 : sz, col);
    }
}
static void drawBackground(void) {
    vgrad(0, 0, SCREEN_W, SCREEN_H, RGB(6, 8, 30), RGB(0, 0, 6));
    vgrad(0, 160, SCREEN_W, 112, RGBA(40, 20, 90, 0), RGBA(40, 20, 90, 55));
}
static void drawFighter(float cx, float cy, unsigned tint) {
    glow(cx, cy + 14, 30, RGBA(80, 160, 255, 70));
    spr(X_PLAYER, cx, cy, 24, tint);
}
static void drawBeam(void) {
    const Alien *b = &g.al[g.capBoss];
    float cx = fx(lerpi(prev.al[g.capBoss].x, b->x) + 12), top = fy(b->y + 14);
    static const unsigned char pulse[4][3] = {{40,90,255},{100,170,255},{80,230,255},{100,170,255}};
    int r, n = g.cap == C_BEAM ? g.beamLen : 4;
    blendAdd();
    for (r = 0; r < n; ++r) {
        int c = (r + (g.frame >> 2)) & 3;
        float hw0 = (2 + r) * 8 * 1.36f * .5f + 6, hw1 = (3 + r) * 8 * 1.36f * .5f + 6;
        float y0 = top + r * 8 * 1.36f, y1 = y0 + 8 * 1.36f;
        trap(cx, y0, hw0, y1, hw1, RGBA(pulse[c][0], pulse[c][1], pulse[c][2], 150), RGBA(pulse[c][0], pulse[c][1], pulse[c][2], 150));
        rect(cx - hw0, y0, 2, y1 - y0, RGBA(200, 240, 255, 120)); rect(cx + hw0 - 2, y0, 2, y1 - y0, RGBA(200, 240, 255, 120));
    }
    blendNormal();
}
static void drawAliens(void) {
    int i, flap = (g.frame >> 4) & 1;
    for (i = 0; i < NAL; ++i) {
        const Alien *a = &g.al[i], *p = &prev.al[i];
        float x, y, cx, cy;
        if (a->st == A_DEAD || (a->st == A_ENTER && a->ent == 0)) continue;
        x = p->st == a->st || p->st == A_ENTER ? lerpi(p->x, a->x) : a->x;
        y = p->st == a->st || p->st == A_ENTER ? lerpi(p->y, a->y) : a->y;
        cx = fx(x + 12); cy = fy(y + 6);
        if (a->st == A_EXPLODE) {
            int f = 2 - (a->timer >> 2);
            glow(cx, cy, 52, RGBA(255, 140, 40, 150 - f * 40));
            spr(X_XA + f, cx, cy, 36, 0xffffffff);
            continue;
        }
        if (a->type == T_BOSS) {
            spr((a->hp == 1 && !g.challenge ? X_BOSSP : X_BOSS) + flap, cx, cy, 34, 0xffffffff);
            if (g.cap == C_CARRY && g.capBoss == i && y >= 32) drawFighter(cx, fy(y - 16 + 7), RGB(255, 110, 110));
        } else spr((a->type == T_BUTTERFLY ? X_BFLY : X_BEE) + flap, cx, cy, 32, 0xffffffff);
    }
}
static void drawShots(void) {
    int i;
    for (i = 0; i < 4; ++i) if (g.ps[i].act) {
        float cx = fx(lerpi(prev.ps[i].x, g.ps[i].x) + 9), cy = fy(lerpi(prev.ps[i].y, g.ps[i].y) + 6);
        blendAdd(); glow(cx, cy, 22, RGBA(80, 200, 255, 160)); blendNormal();
        rect(cx - 1.5f, cy - 6, 3, 12, RGB(220, 250, 255)); rect(cx - 1, cy - 6, 2, 4, RGB(255, 255, 255));
    }
    for (i = 0; i < EBN; ++i) if (g.eb[i].act) {
        float cx = fx(lerpi(prev.eb[i].x, g.eb[i].x) + 12), cy = fy(lerpi(prev.eb[i].y, g.eb[i].y) + 4);
        blendAdd(); glow(cx, cy, 26, RGBA(255, 70, 50, 180)); blendNormal();
        rect(cx - 2, cy - 5, 4, 10, RGB(255, 150, 120)); rect(cx - 1, cy - 4, 2, 8, RGB(255, 240, 160));
    }
}
static void drawPlayer(void) {
    float x = lerpi(prev.px, g.px), cy = fy(g.py + 7);
    int show = g.state == S_INTRO || g.state == S_PLAY || g.state == S_RESULT || g.state == S_CAPTURED;
    if (g.state == S_DYING && !g.dyingQuiet) {
        int f = 3 - (g.stateTimer >> 4);
        float cx = fx(g.px + 12 + (g.dual ? 8 : 0));
        glow(cx, cy, 70 + f * 14, RGBA(255, 200, 100, 120 - f * 20));
        spr(X_XP + f, cx, cy, 52, 0xffffffff);
        return;
    }
    if (!show || (g.state == S_PLAY && (g.invuln & 4))) return;
    if (g.state == S_CAPTURED) { x = g.px; cy = fy(g.py + 7); }
    drawFighter(fx(x + 12), cy, 0xffffffff);
    if (g.dual) drawFighter(fx(x + 28), cy, 0xffffffff);
    if (g.cap == C_RESCUE) drawFighter(fx(lerpi(prev.rx, g.rx) + 12), fy(lerpi(prev.ry, g.ry) + 7), 0xffffffff);
}
static void drawHud(void) {
    char s[24];
    int i;
    text(10, 3, 1, "SCORE", RGB(255, 80, 80)); snprintf(s, sizeof s, "%06d", g.score); text(10, 12, 2, s, RGB(255, 255, 255));
    text(140, 3, 1, "HI-SCORE", RGB(255, 80, 80)); snprintf(s, sizeof s, "%06d", g.hi); text(140, 12, 2, s, RGB(255, 255, 255));
    text(SCREEN_W - 52, 3, 1, "STAGE", RGB(255, 80, 80)); snprintf(s, sizeof s, "%02d", g.stage); text(SCREEN_W - 52, 12, 2, s, RGB(255, 255, 255));
    for (i = 0; i < g.lives && i < 9; ++i) drawFighter(270 + i * 19, 14, 0xffffffff);
}
static void drawMessages(void) {
    char s[32];
    const unsigned white = RGB(255, 255, 255), cyan = RGB(120, 230, 255), gold = RGB(255, 220, 80);
    switch (g.state) {
    case S_INTRO:
        if (g.challenge) ctext(150, 2, "CHALLENGING STAGE", cyan);
        else { snprintf(s, sizeof s, "STAGE %02d", g.stage); ctext(150, 3, s, white); }
        break;
    case S_READY: ctext(214, 3, "READY", white); break;
    case S_DYING: if (g.dyingQuiet) ctext(216, 2, "FIGHTER CAPTURED", RGB(255, 70, 70)); break;
    case S_RESULT: {
        int ratio = g.shots ? g.hits * 100 / g.shots : 0;
        if (ratio > 100) ratio = 100;
        if (g.challenge) {
            snprintf(s, sizeof s, "NUMBER OF HITS %d", g.chalHits); ctext(100, 2, s, white);
            if (g.chalHits == NAL) { ctext(140, 3, "PERFECT!", gold); ctext(180, 2, "BONUS 10000", white); }
        } else {
            ctext(80, 3, "STAGE CLEAR", gold);
            snprintf(s, sizeof s, "SHOTS %5d", g.shots > 999 ? 999 : g.shots); ctext(130, 2, s, white);
            snprintf(s, sizeof s, "HITS  %5d", g.hits > 999 ? 999 : g.hits); ctext(152, 2, s, white);
            snprintf(s, sizeof s, "RATIO %4d%%", ratio); ctext(174, 2, s, cyan);
        }
        break; }
    case S_GAMEOVER:
        ctext(120, 4, "GAME OVER", white);
        if (g.stateTimer == 0 && (g.frame & 32)) ctext(180, 2, "PRESS CROSS", cyan);
        break;
    }
    if (g.paused) { ctext(120, 4, "PAUSED", gold); }
}
static void drawTitle(void) {
    char s[24];
    TVert *v;
    int i;
    float bob = sinf(starTime * .05f) * 3;
    useTex(TX_LOGO);
    v = sceGuGetMemory(2 * sizeof *v);
    sceGuColor(0xffffffff);
    v[0].u = 0; v[0].v = 0; v[1].u = LOGO_W; v[1].v = LOGO_DRAW_H;
    v[0].x = 60; v[0].y = (short)(24 + bob); v[1].x = 420; v[1].y = (short)(24 + bob + LOGO_DRAW_H * 360 / LOGO_W);
    v[0].z = v[1].z = 0;
    sceGuDrawArray(GU_SPRITES, GU_TEXTURE_16BIT | GU_VERTEX_16BIT | GU_TRANSFORM_2D, 2, NULL, v);
    for (i = 0; i < 5; ++i) {
        float cx = 120 + i * 60, cy = 128 + sinf(starTime * .08f + i) * 4;
        int fl = ((int)(starTime * .06f)) & 1;
        if (i == 0) spr(X_BOSS + fl, cx, cy, 34, 0xffffffff);
        else if (i == 1) spr(X_BOSSP + fl, cx, cy, 34, 0xffffffff);
        else if (i == 2) spr(X_BFLY + fl, cx, cy, 32, 0xffffffff);
        else if (i == 3) spr(X_BEE + fl, cx, cy, 32, 0xffffffff);
        else drawFighter(cx, cy, 0xffffffff);
    }
    ctext(170, 2, "HI-SCORE", RGB(255, 80, 80));
    snprintf(s, sizeof s, "%06d", g.hi); ctext(190, 2, s, RGB(255, 255, 255));
    if ((int)(starTime * .02f) & 1) ctext(224, 2, "PRESS CROSS", RGB(120, 230, 255));
    ctext(252, 1, "D-PAD MOVE   CROSS FIRE   SELECT PAUSE   START QUIT", RGB(130, 140, 190));
}

static void detectEffects(void) {
    int i;
    for (i = 0; i < NAL; ++i) if (g.al[i].st == A_EXPLODE && prev.al[i].st != A_EXPLODE)
        burst(fx(g.al[i].x + 12), fy(g.al[i].y + 6), 14, 3.2f, palAlien, 4);
    if (g.state == S_DYING && prev.state != S_DYING && !g.dyingQuiet) burst(fx(g.px + 12), fy(g.py + 7), 40, 5, palShip, 4);
    if (g.state == S_CAPTURED && prev.state != S_CAPTURED) burst(fx(g.px + 12), fy(g.py + 7), 14, 2, palAlien + 2, 2);
    if (g.cap == C_NONE && prev.cap == C_RESCUE && g.dual) burst(fx(g.px + 20), fy(g.py + 7), 20, 3, palShip + 1, 3);
}
static void render(void) {
    sceGuStart(GU_DIRECT, guList);
    curTex = -1; useTex(TX_NONE);
    sceGuDisable(GU_DEPTH_TEST); sceGuEnable(GU_BLEND); blendNormal();
    sceGuShadeModel(GU_SMOOTH);
    sceGuTexMode(GU_PSM_8888, 0, 0, 0);
    sceGuTexFunc(GU_TFX_MODULATE, GU_TCC_RGBA); sceGuTexFilter(GU_NEAREST, GU_NEAREST); sceGuTexWrap(GU_CLAMP, GU_CLAMP);
    drawBackground(); drawStars();
    if (g.state == S_TITLE) drawTitle();
    else {
        if (g.cap == C_BEAM || g.cap == C_PULL) drawBeam();
        drawAliens(); drawShots(); drawPlayer(); drawParticles(); drawHud(); drawMessages();
    }
    if (g.state == S_TITLE) drawParticles();
    sceGuFinish(); sceGuSync(0, 0); sceDisplayWaitVblankStart(); sceGuSwapBuffers();
}

/* ---------------------------------------------------------------- system */
static int exitCallback(int a, int b, void *c) { (void)a; (void)b; (void)c; running = 0; return 0; }
static int callbackThread(SceSize a, void *b) {
    int id; (void)a; (void)b;
    id = sceKernelCreateCallback("Exit Callback", exitCallback, NULL);
    sceKernelRegisterExitCallback(id);
    sceKernelSleepThreadCB();
    return 0;
}
static void setupCallbacks(void) {
    int id = sceKernelCreateThread("callback", callbackThread, 0x11, 0x1000, 0, NULL);
    if (id >= 0) sceKernelStartThread(id, 0, NULL);
}
static void initDisplay(void) {
    sceGuInit(); sceGuStart(GU_DIRECT, guList);
    sceGuDrawBuffer(GU_PSM_8888, (void *)0, BUF_W);
    sceGuDispBuffer(SCREEN_W, SCREEN_H, (void *)(BUF_W * SCREEN_H * 4), BUF_W);
    sceGuOffset(2048 - SCREEN_W / 2, 2048 - SCREEN_H / 2); sceGuViewport(2048, 2048, SCREEN_W, SCREEN_H);
    sceGuScissor(0, 0, SCREEN_W, SCREEN_H); sceGuEnable(GU_SCISSOR_TEST); sceGuDisable(GU_DEPTH_TEST);
    sceGuFinish(); sceGuSync(0, 0); sceGuDisplay(GU_TRUE);
}


#ifdef AUTOPLAY
/* Debug: write the displayed frame as a BMP so screenshots work without a capture permission. */
static void dumpFrame(int n) {
    void *fb; int bw, fmt, x, y;
    static unsigned char row[SCREEN_W * 3];
    unsigned char hdr[54] = {'B','M'};
    char name[64];
    SceUID f;
    unsigned size = 54 + SCREEN_W * 3 * SCREEN_H;
    sceDisplayGetFrameBuf(&fb, &bw, &fmt, PSP_DISPLAY_SETBUF_NEXTFRAME);
    hdr[2] = size; hdr[3] = size >> 8; hdr[4] = size >> 16; hdr[10] = 54; hdr[14] = 40;
    hdr[18] = SCREEN_W & 255; hdr[19] = SCREEN_W >> 8; hdr[22] = SCREEN_H & 255; hdr[23] = SCREEN_H >> 8;
    hdr[26] = 1; hdr[28] = 24;
    sceIoMkdir("ms0:/PSP/shots", 0777);
    snprintf(name, sizeof name, "ms0:/PSP/shots/f%04d.bmp", n);
    f = sceIoOpen(name, PSP_O_WRONLY | PSP_O_CREAT | PSP_O_TRUNC, 0666);
    if (f < 0) return;
    sceIoWrite(f, hdr, 54);
    for (y = SCREEN_H - 1; y >= 0; --y) {
        const unsigned *src = (const unsigned *)((char *)fb + y * bw * 4);
        for (x = 0; x < SCREEN_W; ++x) { row[x * 3] = src[x] >> 16; row[x * 3 + 1] = src[x] >> 8; row[x * 3 + 2] = src[x]; }
        sceIoWrite(f, row, sizeof row);
    }
    sceIoClose(f);
}
#endif

int main(void) {
    SceCtrlData pad;
    unsigned oldButtons = 0;
    int acc = 0, id, frameNo = 0;
    setupCallbacks(); sceCtrlSetSamplingCycle(0); sceCtrlSetSamplingMode(PSP_CTRL_MODE_ANALOG);
    initDisplay(); buildTextures(); loadHighScore();
    id = sceKernelCreateThread("audio", audioThread, 0x12, 0x4000, 0, NULL);
    if (id >= 0) sceKernelStartThread(id, 0, NULL);
    game_init(&g, savedHi); prev = g;
    while (running) {
        Input in;
        unsigned pressed;
        sceCtrlReadBufferPositive(&pad, 1); pressed = pad.Buttons & ~oldButtons; oldButtons = pad.Buttons;
        in.left = (pad.Buttons & PSP_CTRL_LEFT) || pad.Lx < 64;
        in.right = (pad.Buttons & PSP_CTRL_RIGHT) || pad.Lx > 192;
        in.fire = (pad.Buttons & PSP_CTRL_CROSS) != 0;
        in.pause = (pressed & PSP_CTRL_SELECT) != 0;
        in.quit = (pressed & PSP_CTRL_START) != 0;
        if (in.quit && g.state == S_TITLE) break;
#ifdef AUTOPLAY
        if (g.state != S_TITLE || frameNo >= TITLE_HOLD) game_autoplay(&g, &in);
#endif
        /* Fixed 50 Hz logic tick; the display runs at 60 Hz and interpolates. */
        acc += TICK_HZ;
        if (acc >= 60) {
            acc -= 60; prev = g; game_tick(&g, &in);
            if (g.snd) { queueSound((unsigned)g.snd); g.snd = 0; }
            if (g.saveReq) { g.saveReq = 0; if (g.hi != savedHi) saveHighScore(); }
            detectEffects();
        }
        ia = g.paused ? 1.0f : acc / 60.0f;
        audioMute = g.paused;
        if (!g.paused) starTime += 50.0f / 60.0f;
        render();
#ifdef AUTOPLAY
        if (++frameNo >= SHOT_FROM && (frameNo - SHOT_FROM) % SHOT_EVERY == 0 && (frameNo - SHOT_FROM) / SHOT_EVERY < SHOT_MAX) dumpFrame((frameNo - SHOT_FROM) / SHOT_EVERY);
#else
        (void)frameNo;
#endif
    }
    running = 0;
    sceKernelDelayThread(30000);
    sceGuTerm(); sceKernelExitGame();
    return 0;
}
