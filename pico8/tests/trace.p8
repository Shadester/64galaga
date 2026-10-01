pico-8 cartridge // http://www.pico-8.com
version 42
__lua__
-- headless run of game.lua with the scripted input of tests/test_lockstep.py: prints the whole state after every tick
#include ../paths.lua
#include ../game.lua
local p=split(stat(6)," ")
local scen,ticks=p[1],p[2]
game_init(0)
if scen=="challenge" then start_stage_no=3
elseif scen=="capture" then force_capture=true
elseif scen=="late" then start_stage_no=11 end

function n(v)
 if v==true then return 1 elseif v==false then return 0 end
 return v
end
function r(v) return tostr(v,2) end

for t=0,ticks-1 do
 inp.left,inp.right,inp.fire,inp.pause,inp.quit=false,false,false,false,false
 inp.fire=t%7<2
 inp.left=(t\90)%2==1
 inp.right=not inp.left
 if force_capture then
  if state==S_PLAY or state==S_RESULT then inp.fire=false end
  if cap==C_BEAM or cap==C_CARRY or cap==C_DIVING then
   local bx=al[capBoss].x
   inp.left=px>bx+2
   inp.right=px<bx-2
   if cap==C_CARRY then inp.fire=(t&3)<2 end
  end
 end
 if t%1500==1499 or t%1500==1503 then inp.pause=true end
 game_tick()
 local s=""
 for _,v in pairs({state,paused,stateTimer,frame,r(score),r(hi),lives,stage,diff,r(nextBonus),
  challenge,chalVal,chalHits,chalTimer,shots,hits,px,py,invuln,dual,
  dyingQuiet,formDx,formDir,formTimer,entering,diveTimer,cap,capBoss,beamLen,
  beamAcc,beamTimer,rx,ry,snd}) do s..=n(v).." " end
 s=sub(s,1,-2)
 for i=0,nal-1 do
  local x=al[i]
  s..=" "..x.st..","..x.x..","..x.y..","..x.hp..","..x.timer..","..x.dir..","..x.esc..","..n(x.capdive)..","..x.fired..","..x.pstep..","..x.ent..","..x.dly
 end
 for i=0,3 do s..=" "..ps[i].x..","..ps[i].y..","..n(ps[i].act) end
 for i=0,2 do s..=" "..eb[i].x..","..eb[i].y..","..n(eb[i].act)..","..eb[i].dx end
 printh(s)
 snd,saveReq=0,false
end
