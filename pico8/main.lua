-- galaga for pico-8: input, drawing and sound. The rules are in game.lua (the same code the lockstep test runs).
-- c64 coordinates (x 24..343, y 50..249) are stretched to the 128 x 128 screen like the thumby version:
-- screen x = (x - 24) * 0.4, screen y = 14 + (y - 50) * 0.56 (the top 14 rows are the hud). Sprites are not stretched.
-- start arguments (pico8 -run galaga.p8 -p "autoplay stage=3"): autoplay forcecapture few c64 stage=N lives=N diff=N
-- shot=N (the screenshot test: saves the screen after N updates), rec=A gif=B (a GIF of the updates A..B, for docs/)
-- sprite ids: 0 bee, 2 butterfly, 4 boss, 6 boss after a hit (two frames each), 8 ship, 9 captive, 10 and 11 bullets,
-- 12 alien explosion, 15 ship explosion, 19 lives icon
stars={}
for i=0,11 do stars[i]={x=(i*37+11)%128,y=(i*53+7)%114+14,v=1+i%3} end
star_col={5,13,7}
msgs={}
tick=0
auto,quitpulse=false,false

function sp(i,x,y) sspr(i%10*12,i\10*12,12,12,x-6,y-6) end
function cx(x,o) return (x+o-24)*2\5 end
function cy(y,o) return 14+(y+o-50)*14\25 end
function pad(n,w,c) return sub(c..c..c..c..c..c..n,-w) end
function say(t,y,c) print(t,64-#t*2,y-2,c) end

function _init()
 cartdata("shadester_galaga")
 local args=split(stat(6)," ")
 for t in all(args) do arcade=arcade and t~="c64" end -- c64: the rules of the c64 game (32 aliens, 3 bombs), else the arcade rules
 game_init(dget(0))
 for t in all(args) do
  local k,v=unpack(split(t,"="))
  if k=="autoplay" then auto=true
  elseif k=="forcecapture" then force_capture=true
  elseif k=="few" then few=true
  elseif k=="stage" then start_stage_no=v
  elseif k=="lives" then start_lives=v
  elseif k=="diff" then start_diff=v
  elseif k=="shot" then shot=v
  elseif k=="rec" then rec=v
  elseif k=="gif" then gif=v end
 end
 menuitem(1,"title screen",function() quitpulse=true end)
end

function read_input()
 if auto then
  autoplay()
  if force_capture then -- walk under the capture boss so the beam catches, then shoot the carrier
   if state==S_PLAY or state==S_RESULT then inp.fire=false end
   if cap==C_BEAM or cap==C_CARRY or cap==C_DIVING then
    local bx=al[capBoss].x
    inp.left=px>bx+2
    inp.right=px<bx-2
    if cap==C_CARRY then inp.fire=frame&3<2 end
   end
  end
 else
  inp.left,inp.right,inp.fire=btn(0),btn(1),btn(4) or btn(5)
  inp.quit=quitpulse
  quitpulse=false
 end
end

function play(s)
 if s&SND_SHOOT~=0 then sfx(0,0) end
 if s&SND_HIT~=0 then sfx(2,0) end
 if s&SND_EXPLODE~=0 then sfx(1,1) end
 if s&SND_DEATH~=0 then sfx(3,1) end
 if s&SND_SWOOP~=0 then sfx(4,3) end
 for k=0,4 do
  if s&(32<<k)~=0 then sfx(8+k,2) end
 end
end

function step()
 read_input()
 game_tick()
 if snd>0 then play(snd) end
 snd=0
 if saveReq then
  saveReq=false
  if hi~=dget(0) then dset(0,hi) end
  if state==S_TITLE then sfx(-1) end
 end
 if state~=S_TITLE then
  for i=0,11 do
   local s=stars[i]
   s.y+=s.v
   if s.y>=128 then
    s.y=14
    s.x=(s.x*5+17)%128
   end
  end
 end
end

function _update60()
 tick+=1
 if tick%6>0 then step() end -- 50 ticks a second, like the c64
 if tick==shot then extcmd("screen") end
 if tick==rec then extcmd("rec") elseif tick==gif then extcmd("video") end
end

function draw_beam()
 local b=al[capBoss]
 local bx,row0,ph=cx(b.x,12),(b.y-36)\8,(frame\4)&3
 fillp(0x5a5a.1)
 for r=0,beamLen-1 do
  -- the c64 text row under the boss (not offset by 50, as in thumby view.py), 4 high, centred on its middle
  local cells,y=2*r+5,12+((row0+r)*8+4)*14\25
  local x=bx-cells*3\2
  for k=0,cells-1 do
   rectfill(x+k*3,y,x+k*3+2,y+3,({12,6,7,6})[(k+r+ph)%4+1])
  end
 end
 fillp()
end

function draw_msgs()
 local t=state
 if t==S_INTRO then
  if challenge then say("challenging stage",96,12) else say("stage "..pad(stage,2,"0"),96,7) end
 elseif t==S_READY then say("ready",100,7)
 elseif t==S_DYING and dyingQuiet then say("fighter captured",100,8)
 elseif t==S_RESULT then
  if challenge then
   say("number of hits "..chalHits,52,7)
   if chalHits==nal then
    say("perfect!",66,12)
    say("bonus 10000",76,7)
   end
  else
   say("shots "..pad(min(shots,999),3," "),52,7)
   say("hits  "..pad(min(hits,999),3," "),62,7)
   say("ratio "..pad(shots>0 and min(100,hits*100\shots) or 0,3," ").."%",72,12)
  end
 elseif t==S_GAMEOVER then
  say("game over",56,7)
  if stateTimer==0 then say("press fire",72,7) end
 end
end

function _draw()
 cls()
 if state==S_TITLE then
  sspr(0,64,128,64,0,8)
  say("hi-score "..pad(tostr(hi,2),6,"0"),88,8)
  say("press fire",98,7)
  return
 end
 for i=0,11 do
  local s=stars[i]
  pset(s.x,s.y,star_col[s.v])
 end
 -- hud: red labels over white numbers, the lives at the right
 print("score",6,0,8)
 print("hi-score",53,0,8)
 print("stage",103,0,8)
 print(pad(tostr(score,2),6,"0"),7,7,7)
 print(pad(tostr(hi,2),6,"0"),51,7,7)
 print(pad(stage,2,"0"),100,7,7)
 sp(19,115,9)
 print(lives,121,7,7)
 if state~=S_GAMEOVER then
  local anim=(frame\16)&1
  for i=0,nal-1 do
   local a=al[i]
   local st=a.st
   if st~=A_DEAD and not (st==A_ENTER and a.ent==0) then
    local id=4-2*a.ty+anim
    if st==A_EXPLODE then id=12+mid(0,2-a.timer\4,2)
    elseif a.ty==T_BOSS and a.hp==1 and not challenge then id=6+anim end
    sp(id,cx(a.x,12),cy(a.y,6))
   end
  end
  local x,y=cx(px,12),cy(py,7)
  if state==S_DYING then
   if not dyingQuiet then sp(15+mid(0,3-stateTimer\16,3),x,y) end
  elseif state~=S_READY and invuln&4==0 then
   sp(8,x,y)
   if dual then sp(8,x+6,y) end
  end
  if cap==C_CARRY then
   local b=al[capBoss]
   if b.st~=A_DEAD and b.y>=32 then sp(9,cx(b.x,12),cy(b.y-16,7)) end
  elseif cap==C_RESCUE then
   sp(9,cx(rx,12),cy(ry,7))
  end
  for i=0,3 do
   local b=ps[i]
   if b.act then sp(10,cx(b.x,9),cy(b.y,6)) end
  end
  for i=0,ebn-1 do
   local b=eb[i]
   if b.act then sp(11,cx(b.x,12),cy(b.y,4)) end
  end
  if (cap==C_BEAM or cap==C_PULL) and beamLen>0 then draw_beam() end
 end
 draw_msgs()
end
