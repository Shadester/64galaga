-- headless run of game.lua with the scripted input of tests/test_lockstep.py: prints the whole state after every tick
-- the C side is tests/c_trace_arcade.c (psp/game.c)
local p=split(stat(6)," ")
local scen,ticks=p[1],p[2]
game_init(0)
if scen=="challenge" then start_stage_no=3
elseif scen=="capture" then force_capture=true
elseif scen=="late" then start_stage_no=11
elseif scen=="s4" then start_stage_no=4
elseif scen=="beam" then force_capture,beamtest=true,true end

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
 if beamtest then -- the ship cannot be hit, except under the beam
  invuln=(cap==C_BEAM or cap==C_PULL) and 0 or 100
  if cap==C_BEAM then clear_bullets(eb) end
 end
 game_tick()
 local s=""
 for _,v in pairs({state,paused,stateTimer,frame,r(score),r(hi),lives,stage,diff,r(nextBonus),
  challenge,chalVal,chalHits,chalTimer,shots,hits,px,py,invuln,dual,
  dyingQuiet,formDx,formDir,formTimer,entering,cap,capBoss,beamLen,
  beamAcc,beamTimer,rx,ry,snd}) do s..=n(v).." " end
 s=sub(s,1,-2)
 for _,v in pairs({fclk,ff,swayPos,swayDir,breathe,bstep,clk,af,tmr2,hold,wingm,bombFlags,beamPh,beamStep,sortie[0],sortie[1],sortie[2]}) do s..=" "..n(v) end
 for i=0,nal-1 do
  local x=al[i]
  s..=" "..x.st..","..x.x..","..x.y..","..x.hp..","..x.timer..","..x.dir..","..x.esc..","..n(x.capdive)..","..x.pstep..","..x.ent..","..x.dly..","..x.dpath..","..x.bflags..","..x.btmr
 end
 for i=0,3 do s..=" "..ps[i].x..","..ps[i].y..","..n(ps[i].act) end
 for i=0,ebn-1 do s..=" "..eb[i].x..","..eb[i].y..","..n(eb[i].act)..","..eb[i].dx..","..eb[i].ax end
 printh(s)
 snd,saveReq=0,false
end
