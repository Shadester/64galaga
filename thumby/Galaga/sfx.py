# Sound: tones and RTTTL jingles on the engine's four audio channels. The effects follow the C64 game's:
# channel 0 shoot / ship hit, 1 explosions (a tone that jumps around: the engine has no noise voice),
# 2 jingles, 3 the dive swoop and the beam hum. update() runs every game tick and fades the effects.
import engine_audio
from engine_resources import ToneSoundResource, RTTTLSoundResource
import game as G

# The C64 jingles as RTTTL files (the engine reads RTTTL from a file): the duration of a 16th is the C64's 7 / 5 / 4 frames
JINGLES = (
    (G.JG_STAGE, 'jingles/stage.rtttl'),
    (G.JG_OVER, 'jingles/over.rtttl'),
    (G.JG_CAPTURE, 'jingles/capture.rtttl'),
    (G.JG_RESCUE, 'jingles/rescue.rtttl'),
    (G.JG_BONUS, 'jingles/bonus.rtttl'),
)


class Sfx:
    def __init__(self):
        self.tones = [ToneSoundResource() for _ in range(4)]
        self.jingles = [(bit, RTTTLSoundResource(path)) for bit, path in JINGLES]
        self.ch = [engine_audio.play(self.tones[i], i, True) for i in range(4)]
        for c in self.ch:
            c.gain = 0.0
        self.vol = [0.0] * 4
        self.dec = [0.0] * 4
        self.swoop = 0
        self.n = 0
        self.hit_tick = 0
        self.rng = 12345

    def start(self, i, freq, vol, dec):
        self.tones[i].frequency = freq
        self.vol[i] = vol
        self.dec[i] = dec
        self.ch[i].gain = vol

    def play(self, snd):
        """snd: the Game.snd bits of this tick."""
        if snd & G.SND_SHOOT:
            self.start(0, 1200.0, 0.4, 0.07)
        if snd & G.SND_HIT:
            self.start(0, 370.0, 0.5, 0.017)
            self.hit_tick = 30
        if snd & G.SND_EXPLODE:
            self.start(1, 600.0, 0.5, 0.04)
        if snd & G.SND_DEATH:
            self.start(1, 150.0, 0.6, 0.01)
        if snd & G.SND_SWOOP:
            self.swoop = 24
        if snd >> 5:
            for bit, res in self.jingles:
                if snd & bit:
                    engine_audio.play(res, 2, False)

    def update(self):
        """Every game tick: fades, the falling pitch of a hit and of the swoop, the jumping pitch of explosions."""
        for i in (0, 1):
            v = self.vol[i]
            if v > 0.0:
                v -= self.dec[i]
                if v < 0.0:
                    v = 0.0
                self.vol[i] = v
                self.ch[i].gain = v
        if self.hit_tick:
            self.hit_tick -= 1
            self.tones[0].frequency = 150.0 + 7.0 * self.hit_tick
        if self.vol[1] > 0.0:
            self.rng = (self.rng * 75 + 74) % 65537
            self.tones[1].frequency = 80.0 + (self.rng % 700)
        if self.swoop:
            self.swoop -= 1
            self.tones[3].frequency = 15.0 * (2 * self.swoop + 8)
            self.ch[3].gain = 0.15 if self.swoop else 0.0

    def mute(self):
        for i in range(4):
            self.ch[i].gain = 0.0
            self.vol[i] = 0.0
        self.swoop = 0
        self.hit_tick = 0
        engine_audio.stop(2)
