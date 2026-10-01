-- galaga rules: a port of thumby/Galaga/game.py (which ports psp/game.c, which follows the c64 game).
-- no drawing here: main.lua draws, tests/trace.p8 runs this file headless against the c code.
-- c64 coordinates, 50 ticks a second: play area x 24..343, y 50..249. x / y = top left of a 24 x 21 box.
-- pico-8 numbers are 16.16 fixed point and 0 is true: flags are booleans, counters are compared, and
-- score / hi / rng hold a plain integer in the raw bits (n>>16 makes the number whose raw bits are n).
nal=32
mirror_x=344
S_TITLE,S_INTRO,S_PLAY,S_DYING,S_GAMEOVER,S_CAPTURED,S_RESULT,S_READY=0,1,2,3,4,5,6,7
T_BOSS,T_BUTTERFLY,T_BEE=0,1,2
A_DEAD,A_FORM,A_DIVE,A_RETURN,A_EXPLODE,A_BEAM,A_ENTER=0,1,2,3,4,5,6
C_NONE,C_DIVING,C_BEAM,C_PULL,C_CARRY,C_RESCUE=0,1,2,3,4,5
P_A,P_B,P_C,P_D=1,2,3,4
-- sound events, one bit each; main.lua clears snd after it reads it
SND_SHOOT,SND_EXPLODE,SND_HIT,SND_DEATH,SND_SWOOP=1,2,4,8,16
JG_STAGE,JG_OVER,JG_CAPTURE,JG_RESCUE,JG_BONUS=32,64,128,256,512

boss_x={145,171,197,223}
-- fly-in: launch delay (ticks / 2) per slot
entry_delay={40,44,48,52,0,4,8,12,56,60,64,68,80,84,88,92,
 96,100,16,20,24,28,104,108,120,124,128,132,136,140,144,148}
-- difficulty tables, index diff
dive_interval={130,115,100,85,70,58,48,34}
dive_max={1,1,2,2,3,3,4,5}
dive_shots={1,1,1,2,2,2,2,2}
-- raw bits of 50000 and 70000 (too big for a number)
r50000,r70000=0x0.c350,0x1.1170
r999999=0xf.423f

function slot_x(i) return i<4 and boss_x[i+1] or 106+26*((i-4)%7) end
function slot_y(i) return i<4 and 72 or 100+28*((i-4)\7) end

-- a deterministic generator (the c test build has the same): the game is the same on every device.
-- rs is a 32 bit integer in the raw bits; rs*1103515245 (0x41c64e6d) is done in two 16 bit halves
function rseed(s) rs=s end
function rand()
 rs=(rs*0x4e6d+((rs*0x41c6)<<16)+(12345>>16))&0x7fff.ffff
end
-- prand(m): bits 4.. of the next number, masked with m (m = 1, 3 or 31)
function prand(m)
 rand()
 return ((rs>>4)&(m>>16))<<16
end

function entry_path(i)
 local w=1
 if i<4 or (i>=8 and i<12) then w=2
 elseif (i>=12 and i<18) or i==22 or i==23 then w=3
 elseif i>=24 then w=4 end
 if w==1 then return P_C,i==5 or i==7 or i==19 or i==21 end
 if w==2 then return P_D,false end
 if w==3 then return P_D,true end
 return P_C,(i-24)&1==0
end

function new_alien()
 return {x=0,y=0,st=0,ty=0,hp=0,timer=0,dir=0,esc=0,capdive=false,fired=0,path=1,pstep=0,mir=false,ent=0,dly=0}
end

function new_bullet() return {x=0,y=0,act=false,dx=0} end

function game_init(hi_)
 al,ps,eb={},{},{}
 for i=0,nal-1 do al[i]=new_alien() end
 for i=0,3 do ps[i]=new_bullet() end
 for i=0,2 do eb[i]=new_bullet() end
 rs=1
 state=S_TITLE
 paused,prevfire=false,false
 stateTimer,frame,score,lives,stage,diff,nextBonus=0,0,0,0,0,0,0
 hi=hi_
 challenge=false
 chalVal,chalHits,chalTimer,shots,hits=0,0,0,0,0
 px,py=160,230
 invuln,dual,dyingQuiet=0,false,false
 formDx,formDir,formTimer,entering,diveTimer=0,0,0,0,0
 cap,capBoss,beamLen,beamAcc,beamTimer,rx,ry=0,0,0,0,0,0,0
 snd,saveReq=0,false
 -- debug starts, as the -D flags of the other ports
 start_stage_no,start_diff,start_lives=1,0,3
 few,force_capture=false,false
 inp={left=false,right=false,fire=false,pause=false,quit=false}
end

-- ---- helpers ----
function clear_bullets(b)
 for i=0,#b do b[i].x,b[i].y,b[i].act,b[i].dx=0,0,false,0 end
end

function add_score(n)
 score+=n>>16
 if score>r999999 then score=r999999 end
 if score>hi then hi=score end
 while score>=nextBonus do
  if lives<9 then lives+=1 end
  nextBonus+=nextBonus==20000>>16 and r50000 or r70000
  snd|=JG_BONUS
 end
end

function setup_stage()
 challenge=stage&3==3
 chalVal=min(900,100*((stage+1)\4))
 chalHits,chalTimer,shots,hits=0,0,0,0
 formDx,formDir,formTimer=0,3,0
 diveTimer=dive_interval[diff]
 cap,beamLen=C_NONE,0
 clear_bullets(ps)
 clear_bullets(eb)
 for i=0,nal-1 do
  local a=new_alien()
  al[i]=a
  if challenge then
   a.ty=i\8==1 and T_BUTTERFLY or i\8==3 and T_BOSS or T_BEE
  else
   a.ty=i<4 and T_BOSS or i<18 and T_BUTTERFLY or T_BEE
  end
  a.hp=(not challenge and a.ty==T_BOSS) and 2 or 1
  a.st=A_ENTER
  a.y=255
  if challenge then
   a.path=(i\8)&1==1 and P_B or P_A
   a.mir=i\8>=2
  else
   a.path,a.mir=entry_path(i)
   a.dly=2*entry_delay[i+1]
  end
 end
 if few then -- debug: only three bees
  for i=0,28 do al[i].st=A_DEAD end
 end
end

function start_stage()
 setup_stage()
 state=S_INTRO
 stateTimer=120
 snd|=JG_STAGE
end

function start_game()
 -- frame * 2654435761 + 1 (0x9e3779b1) mod 2^32, in two halves
 rseed(((frame>>16)*0x79b1)+(((frame>>16)*-0x61c9)<<16)+(1>>16))
 score,lives,stage,diff=0,start_lives,start_stage_no,1
 if stage~=1 then diff=min(8,1+(stage-1-stage\4)) end
 if start_diff>0 then diff=start_diff end
 nextBonus=20000>>16
 dual,cap=false,C_NONE
 px,py=160,230
 invuln,dyingQuiet=0,false
 start_stage()
end

function game_over()
 state=S_GAMEOVER
 stateTimer=90
 snd|=JG_OVER
 saveReq=true
end

-- ---- player ----
function player_hit(side)
 if dual then
  dual=false
  if side==0 then px+=16 end
  invuln=90
  snd|=SND_HIT
  return
 end
 lives-=1
 state=S_DYING
 stateTimer=63
 dyingQuiet=false
 clear_bullets(eb)
 clear_bullets(ps)
 snd|=SND_HIT|SND_DEATH
end

function update_player(fire_press)
 local maxx=dual and 304 or 320
 if inp.left then px-=2 end
 if inp.right then px+=2 end
 px=mid(24,px,maxx)
 if not fire_press then return end
 for n=0,dual and 1 or 0 do
  for i=n*2,n*2+1 do
   local b=ps[i]
   if not b.act then
    b.act=true
    b.x=px+3+16*n
    b.y=214
    -- the result screen shows the stage's shots: later ones do not count
    if state~=S_RESULT then shots+=1 end
    snd|=SND_SHOOT
    break
   end
  end
 end
end

function update_pshots()
 for i=0,3 do
  local b=ps[i]
  if b.act then
   b.y-=4
   if b.y<20 then b.act=false end
  end
 end
end

-- ---- aliens ----
function release_capture(boss)
 if cap>0 and cap~=C_RESCUE and capBoss==boss then cap=C_NONE end
end

function alien_hit(i)
 local a=al[i]
 local dive=a.st==A_DIVE or a.st==A_ENTER
 local pts
 hits+=1
 if a.hp>1 then
  a.hp-=1
  snd|=SND_SHOOT
  return
 end
 if challenge then
  chalHits+=1
  pts=chalVal
 elseif a.ty==T_BOSS then
  local n=0
  if dive then
   for j=0,nal-1 do
    local e=al[j]
    if e.esc==i+1 and (e.st==A_DIVE or e.st==A_RETURN) then n+=1 end
   end
  end
  pts=dive and 400<<n or 150
 elseif a.ty==T_BUTTERFLY then
  pts=dive and 160 or 80
 else
  pts=dive and 100 or 50
 end
 if a.ty==T_BOSS and cap>0 and capBoss==i then
  if cap==C_CARRY and (a.st==A_DIVE or a.st==A_RETURN) then
   cap=C_RESCUE
   rx=a.x
   ry=a.y-16
   pts+=1000
   snd|=JG_RESCUE
  else
   cap=C_NONE -- captive lost, or capture cancelled (beam vanishes)
  end
 end
 a.st=A_EXPLODE
 a.timer=11
 snd|=SND_EXPLODE
 add_score(pts)
end

function path_step(a)
 local p=paths[a.path]
 local k=a.pstep+1
 local dx=sub(p[4],k,k)-3
 a.x+=a.mir and -dx or dx
 a.y+=sub(p[5],k,k)-3
 a.pstep+=1
end

function path_launch(a)
 local p=paths[a.path]
 a.ent=1
 a.pstep=0
 a.x=a.mir and mirror_x-p[1] or p[1]
 a.y=p[2]
end

function update_formation()
 local n=0
 for i=0,nal-1 do
  if al[i].st==A_ENTER then n+=1 end
 end
 entering=n
 if n>0 or challenge then return end
 formTimer+=1
 if formTimer>=10-diff then
  formTimer=0
  formDx+=formDir
  if formDx>=42 then formDir=-3 end
  if formDx<=-42 then formDir=3 end
 end
end

-- one step of v towards t, n long
function toward(v,t,n)
 return v<t and n or v>t and -n or 0
end

function update_entry()
 for i=0,nal-1 do
  local a=al[i]
  if a.st==A_ENTER then
   if a.ent==0 then
    a.dly-=1
    if a.dly<=0 then path_launch(a) end
   elseif a.ent==1 then
    if a.pstep>=paths[a.path][3] then a.ent=2 else path_step(a) end
   else
    local tx,ty=slot_x(i)+formDx,slot_y(i)
    a.x+=toward(a.x,tx,2)
    a.y+=toward(a.y,ty,2)
    if abs(a.x-tx)<=3 and abs(a.y-ty)<=3 then
     a.st=A_FORM
     a.x=tx
     a.y=ty
    end
   end
  end
 end
end

function update_challenge()
 chalTimer+=1
 for i=0,nal-1 do
  local a=al[i]
  if a.st==A_ENTER then
   if a.ent==0 then
    if chalTimer>=(i\8)*55+(i&7)*6 then path_launch(a) end
   elseif a.pstep>=paths[a.path][3] then
    a.st=A_DEAD
   else
    path_step(a)
   end
  end
 end
end

function spawn_ebullet(a)
 local d=px-a.x
 for i=0,2 do
  local b=eb[i]
  if not b.act then
   b.act=true
   b.x=a.x
   b.y=a.y+8
   b.dx=abs(d)<16 and 0 or d>0 and 1 or -1
   return
  end
 end
end

function start_dive(i,capture,peel)
 local a=al[i]
 a.st=A_DIVE
 a.timer=peel
 a.fired=0
 a.capdive=capture
 if capture then
  a.dir=a.x<px and 1 or -1
 else
  a.dir=a.x>=184 and 1 or -1
 end
 snd|=SND_SWOOP
 if capture then
  cap=C_DIVING
  capBoss=i
 end
end

function dive_step(i)
 local a=al[i]
 local dy=diff>=5 and 3 or 2
 if a.timer>0 then
  a.timer-=1
  a.x+=2*a.dir
  a.y+=1
  return
 end
 a.y+=dy
 if a.capdive or frame&1==1 then a.x+=toward(a.x,px,1) end
 if a.esc==0 and not a.capdive then
  local mask=diff<=2 and 1 or 0
  if (a.fired==0 and a.y>=100) or (a.fired==1 and dive_shots[diff]==2 and a.y>=150) then
   a.fired+=1
   if prand(mask)==0 then spawn_ebullet(a) end
  end
 end
 if a.capdive and a.y>=196 then
  a.st=A_BEAM
  cap=C_BEAM
  beamLen,beamAcc=0,0
  beamTimer=180
 elseif a.y>=244 then
  a.st=A_RETURN
  a.y=0
  a.capdive=false
 end
end

function update_aliens()
 for i=0,nal-1 do
  local a=al[i]
  local st=a.st
  if st==A_FORM then
   a.x=slot_x(i)+formDx
   a.y=slot_y(i)
  elseif st==A_EXPLODE then
   a.timer-=1
   if a.timer<0 then a.st=A_DEAD end
  elseif st==A_DIVE then
   dive_step(i)
  elseif st==A_RETURN then
   a.x=slot_x(i)+formDx
   a.y+=2
   if a.y>=slot_y(i) then
    a.y=slot_y(i)
    a.st=A_FORM
    a.esc=0
   end
  end
 end
end

function select_dive()
 if entering>0 or challenge then return end
 diveTimer-=1
 if diveTimer>0 then return end
 diveTimer=dive_interval[diff]
 local away=0
 for j=0,nal-1 do
  local a=al[j]
  if a.esc==0 and (a.st==A_DIVE or a.st==A_RETURN or a.st==A_BEAM) then away+=1 end
 end
 if away>=dive_max[diff] then return end
 if force_capture and cap==0 and not dual and al[1].st==A_FORM then
  start_dive(1,true,20)
  return
 end
 local pick=-1
 if cap==0 and not dual and prand(1)==1 then
  local i=prand(3)
  if al[i].st==A_FORM then pick=i end
 end
 local tries=0
 while pick<0 and tries<8 do
  local i=prand(31)
  if al[i].st==A_FORM then pick=i end
  tries+=1
 end
 if pick<0 then return end
 if al[pick].ty==T_BOSS and cap==0 and not dual then
  start_dive(pick,true,20)
  return
 end
 start_dive(pick,false,20)
 if al[pick].ty==T_BOSS and (cap>0 or dual) then
  for k=0,1 do
   local e=al[5+pick+k]
   if e.st==A_FORM then
    start_dive(5+pick+k,false,k==1 and 32 or 26)
    e.esc=pick+1
   end
  end
 end
end

function update_ebullets()
 for i=0,2 do
  local b=eb[i]
  if b.act then
   b.y+=3
   if frame&1==1 then b.x+=b.dx end
   if b.y>=250 then b.act=false end
  end
 end
end

function update_collisions()
 for i=0,3 do
  local b=ps[i]
  if b.act then
   for j=0,nal-1 do
    local a=al[j]
    if not (a.st==A_DEAD or a.st==A_EXPLODE or (a.st==A_ENTER and a.ent==0)) then
     if b.y-8<=a.y and a.y<b.y+8 and a.x-6<=b.x and b.x<a.x+12 then
      b.act=false
      alien_hit(j)
      break
     end
    end
   end
  end
 end
 if state~=S_PLAY or invuln>0 then return end
 for i=0,2 do
  if state~=S_PLAY then break end
  local b=eb[i]
  if b.act and b.y>=227 and b.y<=240 then
   for j=0,dual and 1 or 0 do
    local sx=px+16*j
    if sx-6<=b.x and b.x<=sx+7 then
     b.act=false
     player_hit(j)
     break
    end
   end
  end
 end
 local j=0
 while j<nal and state==S_PLAY and invuln==0 and not challenge do -- challenge aliens never ram
  local a=al[j]
  if a.st==A_DIVE or (a.st==A_ENTER and a.ent>0) then
   for s=0,dual and 1 or 0 do
    local sx=px+16*s
    if py-7<=a.y and a.y<=py+8 and sx-8<a.x and a.x<=sx+8 then
     if a.capdive then release_capture(j) end -- ramming boss drops its captive
     if a.ty==T_BOSS and cap==C_CARRY and capBoss==j then cap=C_NONE end
     a.st=A_EXPLODE
     a.timer=11
     snd|=SND_EXPLODE
     player_hit(s)
     break
    end
   end
  end
  j+=1
 end
end

-- ---- tractor beam, capture, rescue ----
function update_capture()
 if cap==C_BEAM then
  local b=al[capBoss]
  if frame&31==0 then snd|=SND_SWOOP end
  if beamLen<4 then
   beamAcc+=1
   if beamAcc>=8 then
    beamAcc=0
    beamLen+=1
   end
  elseif state==S_PLAY and invuln==0 and b.x-20<=px and px<=b.x+19 then
   cap=C_PULL
   state=S_CAPTURED
   dual=false
   clear_bullets(ps)
   snd|=JG_CAPTURE
  else
   beamTimer-=1
   if beamTimer<=0 then
    cap=C_NONE
    b.st=A_RETURN
    b.y=0
   end
  end
 elseif cap==C_RESCUE then
  local tx=px+16
  ry=min(230,ry+3)
  rx+=toward(rx,tx,2)
  if ry==230 and state==S_PLAY and rx-tx>=-4 and rx-tx<=3 then
   cap=C_NONE
   dual=true
   if px>304 then px=304 end
   snd|=JG_RESCUE
  end
 end
end

function update_captured()
 local b=al[capBoss]
 update_ebullets()
 py-=2
 if py-b.y>=22 then return end
 py=230
 cap=C_CARRY
 b.st=A_RETURN
 b.y=0
 b.capdive=false
 lives-=1
 if lives<=0 then
  game_over()
  return
 end
 state=S_DYING
 stateTimer=100
 dyingQuiet=true
end

function next_stage()
 if not challenge and diff<8 then diff+=1 end
 stage+=1
 start_stage()
end

function enter_result()
 state=S_RESULT
 stateTimer=150
 if challenge and chalHits==nal then add_score(10000) end
end

function move_world()
 update_formation()
 update_entry()
 update_aliens()
end

function game_tick()
 local fire_press=inp.fire and not prevfire
 prevfire=inp.fire
 if state==S_TITLE then
  if fire_press then start_game() end
  frame+=1
  return
 end
 if inp.pause and state==S_PLAY then paused=not paused end
 if paused then return end
 if inp.quit and state~=S_GAMEOVER then
  state=S_TITLE
  saveReq=true
  snd=0
  return
 end
 frame+=1
 local st=state
 if st==S_INTRO then
  stateTimer-=1
  if stateTimer<=0 then state=S_PLAY end
 elseif st==S_PLAY then
  if invuln>0 then invuln-=1 end
  update_player(fire_press)
  update_pshots()
  if challenge then
   update_challenge()
   update_aliens()
  else
   move_world()
   select_dive()
   update_ebullets()
  end
  update_collisions()
  update_capture()
  if state~=S_PLAY then return end
  local alive=0
  for i=0,nal-1 do
   if al[i].st~=A_DEAD then alive+=1 end
  end
  if alive==0 and cap~=C_RESCUE then enter_result() end
 elseif st==S_DYING then
  if challenge then
   update_aliens()
  else
   move_world()
   update_ebullets()
   update_capture()
  end
  stateTimer-=1
  if stateTimer<=0 then
   if lives<=0 then
    game_over()
   else
    state=S_READY
    stateTimer=90
   end
  end
 elseif st==S_READY then
  if challenge then update_aliens() else move_world() end
  stateTimer-=1
  if stateTimer<=0 then
   state=S_PLAY
   px=160
   invuln=120
  end
 elseif st==S_CAPTURED then
  move_world()
  update_capture()
  update_captured()
 elseif st==S_RESULT then
  update_player(fire_press)
  update_pshots()
  stateTimer-=1
  if stateTimer<=0 then next_stage() end
 elseif st==S_GAMEOVER then
  if stateTimer>0 then
   stateTimer-=1
  elseif fire_press then
   state=S_TITLE
  end
 end
end

-- synthetic input for unattended runs: sweep, fire, press fire on menus
function autoplay()
 inp.pause,inp.quit=false,false
 inp.fire=frame&15<2
 inp.left=frame\128&1==1
 inp.right=not inp.left
end
