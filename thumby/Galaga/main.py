# Galaga for the Thumby Color: the engine part. The rules are in game.py, what is on the screen in view.py.
#
# Desktop keys (tools/run.sh): A / D move, . or , fire, Return pause, Left Shift quit to the title.
# Thumby Color: LEFT / RIGHT move, A or B fire, MENU pause, LB quit to the title.
# Arguments (the desktop run): autoplay | stage=N | lives=N | diff=N | few | forcecapture | nofire | dieat=N | pauseat=N |
# quitat=N | nosave | record=FILE:EVERY:COUNT (frames of the screen as RGB565, see tools/rawframes.py)
import engine_main
import sys
import time
import engine
import engine_io
import engine_draw
import engine_save
from engine_nodes import CameraNode, Sprite2DNode, Text2DNode, Rectangle2DNode
from engine_resources import TextureResource
from engine_math import Vector2
from engine_draw import Color

import game as G
import view as V
import sprite_ids as S
import sfx as SFX

args = {}
for a in sys.argv[1:]:
    k, _, v = a.partition('=')
    args[k] = v
AUTOPLAY = 'autoplay' in args
RECORD = args.get('record')

engine.fps_limit(1000 if RECORD else 50)
NOSAVE = 'nosave' in args                 # tests: the hi-score is neither read nor written
if not NOSAVE:
    try:
        engine_save.set_location("galaga.save")
    except RuntimeError:                  # started directly (desktop): the launcher has not set the saves folder
        engine_save._init_saves_dir("/Saves/Galaga")
        engine_save.set_location("galaga.save")

game = G.Game(0 if NOSAVE else engine_save.load("hi", 0))
if 'stage' in args:
    game.start_stage_no = int(args['stage'])
if 'lives' in args:
    game.start_lives = int(args['lives'])
if 'diff' in args:
    game.start_diff = int(args['diff'])
game.few = 'few' in args
FORCECAPTURE = 'forcecapture' in args
game.force_capture = FORCECAPTURE
NOFIRE = 'nofire' in args
DIEAT, PAUSEAT, QUITAT = int(args.get('dieat', -1)), int(args.get('pauseat', -1)), int(args.get('quitat', -1))
inp = G.Input()
scene = V.Scene()
sound = SFX.Sfx()

# ---- nodes: back to front by layer ----
camera = CameraNode()
black = engine_draw.black
tex = TextureResource("sprites.bmp")
beam_tex = TextureResource("beams.bmp")
title_tex = TextureResource("title.bmp")

star_colors = (Color(0.25, 0.25, 0.4), Color(0.5, 0.5, 0.6), Color(0.9, 0.9, 1.0))
stars = [Rectangle2DNode(width=1, height=1, color=star_colors[scene.star_v[i] - 1], position=Vector2(0, 0), layer=0)
         for i in range(V.NUM_STARS)]
title = Sprite2DNode(texture=title_tex, frame_count_x=1, frame_count_y=1, transparent_color=black, playing=False,
                     position=Vector2(0, -28), layer=1)
beams = [Sprite2DNode(texture=beam_tex, frame_count_x=4, frame_count_y=4, transparent_color=black, playing=False,
                      position=Vector2(0, 0), opacity=0.0, layer=2) for _ in range(4)]
sprites = [Sprite2DNode(texture=tex, frame_count_x=S.COLS, frame_count_y=(S.COUNT + S.COLS - 1) // S.COLS,
                        transparent_color=black, playing=False, position=Vector2(0, 0), opacity=0.0,
                        layer=3 if i < 32 else 4)
           for i in range(V.N_SLOTS)]
last_sid = [-1] * V.N_SLOTS

TEXT_COLORS = (Color(1, 1, 1), Color(1, 0.25, 0.1), Color(0.4, 0.9, 1), Color(0.5, 0.6, 1))
hud_nodes = [Text2DNode(text='', position=Vector2(0, 0), color=TEXT_COLORS[c], layer=6, opacity=0.0)
             for c in (V.WHITE, V.WHITE, V.BLUE, V.BLUE)]
msg_nodes = [Text2DNode(text='', position=Vector2(0, 0), color=TEXT_COLORS[0], layer=6, opacity=0.0)
             for _ in range(V.MAX_MSG)]
last_msg = [''] * V.MAX_MSG
last_hud = ['', '', '', '']


def place_hud():
    # left aligned lines: the position is the centre of the text, about 6 pixels a character
    hud_nodes[0].position.x = -62 + 36
    hud_nodes[0].position.y = -64 + 4
    hud_nodes[1].position.x = 62 - 21
    hud_nodes[1].position.y = -64 + 4
    hud_nodes[2].position.x = -62 + 21
    hud_nodes[2].position.y = -64 + 11
    hud_nodes[3].position.x = 62 - 24
    hud_nodes[3].position.y = -64 + 11


place_hud()


def render():
    """Move the nodes to what the scene says (only what changed)."""
    scene.update(game)
    if not game.paused:
        scene.move_stars()
    title.opacity = 1.0 if scene.title else 0.0
    for i in range(V.NUM_STARS):
        n = stars[i]
        n.opacity = 0.0 if scene.title else 1.0
        n.position.x = scene.star_x[i] - 64
        n.position.y = scene.star_y[i] - 64
    sid = scene.sid
    for i in range(V.N_SLOTS):
        n = sprites[i]
        s = sid[i]
        if s < 0:
            if last_sid[i] >= 0:
                n.opacity = 0.0
                last_sid[i] = -1
            continue
        if s != last_sid[i]:
            n.frame_current_x = s % S.COLS
            n.frame_current_y = s // S.COLS
            n.opacity = 1.0
            last_sid[i] = s
        p = n.position
        p.x = scene.sx[i] - 64
        p.y = scene.sy[i] - 64
    for r in range(4):
        b = beams[r]
        if r < scene.beam_n:
            f = scene.bf[r]
            b.frame_current_x = f & 3
            b.frame_current_y = f >> 2
            b.position.x = scene.bx[r] - 64
            b.position.y = scene.by[r] - 64
            b.opacity = 1.0
        else:
            b.opacity = 0.0
    # texts
    if scene.hud:
        hud = (scene.score, scene.lives, scene.hi, scene.level)
        for i in range(4):
            if hud[i] != last_hud[i]:
                last_hud[i] = hud[i]
                hud_nodes[i].text = hud[i]
            hud_nodes[i].opacity = 1.0
    else:
        for i in range(4):
            hud_nodes[i].opacity = 0.0
    for i in range(V.MAX_MSG):
        n = msg_nodes[i]
        t = scene.msg[i]
        if t:
            if t != last_msg[i]:
                last_msg[i] = t
                n.text = t
            n.position.x = 0
            n.position.y = scene.msg_y[i] - 64
            n.color = TEXT_COLORS[scene.msg_col[i]]
            n.opacity = 1.0
        elif last_msg[i]:
            last_msg[i] = ''
            n.opacity = 0.0


def read_input(pulses):
    """Buttons -> the game's Input; pause / quit are one-tick pulses (pulses = [pause, quit] since the last tick)."""
    if AUTOPLAY:
        G.autoplay(game, inp)
        if NOFIRE and game.state == G.S_PLAY:
            inp.fire = 0
        if FORCECAPTURE:                  # walk under the capture boss so the beam catches, then shoot the carrier
            if game.state == G.S_PLAY or game.state == G.S_RESULT:
                inp.fire = 0
            if game.cap == G.C_BEAM or game.cap == G.C_CARRY or game.cap == G.C_DIVING:
                bx = game.al[game.capBoss].x
                inp.left = 1 if game.px > bx + 2 else 0
                inp.right = 1 if game.px < bx - 2 else 0
                if game.cap == G.C_CARRY:
                    inp.fire = 1 if (game.frame & 3) < 2 else 0
        if ticks == PAUSEAT:
            inp.pause = 1
        if ticks == QUITAT:
            inp.quit = 1
        return
    inp.left = 1 if engine_io.LEFT.is_pressed else 0
    inp.right = 1 if engine_io.RIGHT.is_pressed else 0
    inp.fire = 1 if (engine_io.A.is_pressed or engine_io.B.is_pressed) else 0
    inp.pause = pulses[0]
    inp.quit = pulses[1]
    pulses[0] = pulses[1] = 0


def game_tick(pulses):
    global ticks
    read_input(pulses)
    if ticks == DIEAT and game.state == G.S_PLAY:
        game.player_hit(0)
    game.tick(inp)
    if game.snd:
        sound.play(game.snd)
        game.snd = 0
    if game.paused:
        sound.mute()
    sound.update()
    ticks += 1
    if game.saveReq:
        game.saveReq = 0
        if not NOSAVE and game.hi != engine_save.load("hi", 0):
            engine_save.save("hi", game.hi)
        if game.state == G.S_TITLE:
            sound.mute()


def record_setup():
    path, every, count = RECORD.split(':')
    return open(path, 'wb'), int(every), int(count)


def dump(f):
    fb = engine_draw.front_fb()
    row = bytearray(256)
    for y in range(128):
        for x in range(128):
            p = fb.pixel(x, y)
            row[x * 2] = p >> 8
            row[x * 2 + 1] = p & 255
        f.write(row)


pulses = [0, 0]
acc = 0
last = time.ticks_ms()
ticks = 0
if RECORD:
    rec, rec_every, rec_count = record_setup()
    dumped = 0
    pending = False
while True:
    if not engine.tick():
        continue
    if RECORD:
        if pending:
            dump(rec)
            dumped += 1
            pending = False
            if dumped >= rec_count:
                rec.close()
                break
        game_tick(pulses)
        render()
        pending = ticks % rec_every == 0
        continue
    if engine_io.MENU.is_just_pressed:
        pulses[0] = 1
    if engine_io.LB.is_just_pressed:
        pulses[1] = 1
    now = time.ticks_ms()
    acc += time.ticks_diff(now, last)
    last = now
    steps = 0
    while acc >= 20 and steps < 3:
        game_tick(pulses)
        acc -= 20
        steps += 1
    if acc > 60:
        acc = 0
    render()
