/* Sound: the four Paula channels. 0 shoot / hit, 1 explosions, 2 the jingles (a looped wave, one note after the other), 3 the swoop. */
#ifndef AUDIO_H
#define AUDIO_H
void audio_init(void);
void audio_play(int snd);      /* the Game.snd bits of a tick */
void audio_tick(void);         /* once a tick: steps the jingle */
void audio_mute(void);
#endif
