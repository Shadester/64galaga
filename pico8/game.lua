-- galaga rules: a port of thumby/Galaga/game.py (which ports psp/game.c, which follows the c64 game).
-- no drawing here: main.lua draws, tests/trace.p8 runs this file headless against the c code.
-- c64 coordinates, 50 ticks a second: play area x 24..343, y 50..249. x / y = top left of a 24 x 21 box.
-- pico-8 numbers are 16.16 fixed point and 0 is true: flags are booleans, counters are compared, and
-- score / hi hold a plain integer in the raw bits (n>>16 makes the number whose raw bits are n).
-- the arcade rules (40 aliens, 8 bombs, see ../ARCADE.md and psp/game.c)
S_TITLE,S_INTRO,S_PLAY,S_DYING,S_GAMEOVER,S_CAPTURED,S_RESULT,S_READY=0,1,2,3,4,5,6,7
T_BOSS,T_BUTTERFLY,T_BEE=0,1,2
A_DEAD,A_FORM,A_DIVE,A_RETURN,A_EXPLODE,A_BEAM,A_ENTER=0,1,2,3,4,5,6
C_NONE,C_DIVING,C_BEAM,C_PULL,C_CARRY,C_RESCUE=0,1,2,3,4,5
-- sound events, one bit each; main.lua clears snd after it reads it
SND_SHOOT,SND_EXPLODE,SND_HIT,SND_DEATH,SND_SWOOP=1,2,4,8,16
JG_STAGE,JG_OVER,JG_CAPTURE,JG_RESCUE,JG_BONUS=32,64,128,256,512

-- raw bits of 50000 and 70000 (too big for a number)
r50000,r70000=0x0.c350,0x1.1170
r999999=0xf.423f

function slot_x(i) return a_sl[2*i+1] end
function slot_y(i) return a_sl[2*i+2] end
-- where a slot is now: the swing of the formation, and the breathing of its columns and rows
function slot_px(i)
 local x=slot_x(i)+formDx
 if breathe then
  local c,k=a_col[i+1],bstep*10+1
  x+=c<5 and a_br[k+c] or -a_br[k+9-c]
 end
 return x
end
function slot_py(i)
 return slot_y(i)+(breathe and a_br[bstep*10+6+a_row[i+1]] or 0)
end

-- the numbers of the arcade rules (arcade_data.lua): lists of integers in strings
function d36(c) return c-(c<58 and 48 or 87) end
function dec(s)
 local t,i={},1
 while i<=#s do
  local v=d36(ord(s,i))
  if v==35 then
   v=d36(ord(s,i+1))*36+d36(ord(s,i+2))-500
   i+=2
  else v-=8 end
  add(t,v)
  i+=1
 end
 return t
end
-- integer division that rounds towards zero, like C
function td(a,b)
 local q=abs(a)\abs(b)
 return (a<0)~=(b<0) and -q or q
end
-- the steps of the paths are a bit stream in free memory (map 0x2000.., sprite sheet 0x600..), see tools/gen_arcade_p8.py
function rb() -- the next bit (bk: the byte, bb: the bit in it: a bit counter would pass 32767, the biggest number)
 local v=(peek(bk<4096 and 0x2000+bk or bk-2560)>>bb)&1
 bb+=1
 if bb==8 then bb=0 bk+=1 end
 return v
end
function rv() -- the next value: 0 10 110 1110 11110, or 11111 and 9 bits
 for i=1,5 do
  if rb()==0 then return ({0,1,-1,2,-2})[i] end
 end
 local v=0
 for i=0,8 do v+=rb()<<i end
 return v-256
end

function arc_data()
 a_p,a_d,a_w,bk,bb={},{},{},0,0
 for l in all({a_path,a_dive}) do
  for s in all(l) do
   local h=dec(s)
   local m=#h-1
   local n=h[m+1]
   for c=0,1 do
    local v=0
    for j=1,n do
     v+=rv()
     h[m+2*j-1+c]=v
    end
   end
   add(l==a_path and a_p or a_d,h)
  end
 end
 a_sl,a_rm,a_st,a_map,a_row,a_side,a_col,a_eb,a_wg,a_rd,a_be,a_bt=dec(a_slot),dec(a_rowhdr),dec(a_stage),dec(a_dmap),dec(a_slotrow),dec(a_slotside),dec(a_slotcol),dec(a_ebomb),dec(a_wing),dec(a_red),dec(a_bee),dec(a_bomb)
 for s in all(a_wave) do
  local w,t=dec(s),0
  for k=1,#w,3 do
   t+=w[k]
   w[k]=t
  end
  add(a_w,w)
 end
 a_br=dec(a_breath)
 for k=11,640 do a_br[k]+=a_br[k-10] end
end
-- the row of the stage table that stage s uses (the arcade repeats stages 23..26)
function arc_sn()
 local s=stage
 if s>26 then s=23+((s-23)&3) end
 return (s-1)*12+2
end

function new_alien()
 return {x=0,y=0,st=0,ty=0,hp=0,timer=0,dir=0,esc=0,capdive=false,path=1,pstep=0,ent=0,dly=0,dpath=0,bflags=0,btmr=0}
end

function new_bullet() return {x=0,y=0,act=false,dx=0,ax=0} end

function game_init(hi_)
 al,ps,eb={},{},{}
 nal,ebn=40,8
 arc_data()
 for i=0,nal-1 do al[i]=new_alien() end
 for i=0,3 do ps[i]=new_bullet() end
 for i=0,ebn-1 do eb[i]=new_bullet() end
 state=S_TITLE
 paused,prevfire=false,false
 stateTimer,frame,score,lives,stage,diff,nextBonus=0,0,0,0,0,0,0
 hi=hi_
 challenge=false
 chalVal,chalHits,chalTimer,shots,hits=0,0,0,0,0
 px,py=160,230
 invuln,dual,dyingQuiet=0,false,false
 formDx,formDir,formTimer,entering=0,0,0,0
 fclk,ff,swayPos,swayDir,breathe,bstep,clk,af,tmr2,hold,wingm,bombFlags,beamPh,beamStep=0,0,0,0,false,0,0,0,0,0,0,0,0,0
 sortie={[0]=0,0,0}
 cap,capBoss,beamLen,beamAcc,beamTimer,rx,ry=0,0,0,0,0,0,0
 snd,saveReq=0,false
 -- debug starts, as the -D flags of the other ports
 start_stage_no,start_diff,start_lives=1,0,3
 few,force_capture=false,false
 inp={left=false,right=false,fire=false,pause=false,quit=false}
end

-- ---- helpers ----
function clear_bullets(b)
 for i=0,#b do b[i].x,b[i].y,b[i].act,b[i].dx,b[i].ax=0,0,false,0,0 end
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
 local row=a_st[arc_sn()-1]
 challenge=a_rm[row*3+1]==1
 chalVal=100
 fclk,ff,swayPos,swayDir,breathe,bstep=0,0,0,1,false,0
 clk,af,wingm,bombFlags,hold,tmr2=0,0,0,0,0,120
 sortie={[0]=22,2,2}
 chalHits,chalTimer,shots,hits=0,0,0,0
 formDx,formDir,formTimer=0,3,0
 cap,beamLen=C_NONE,0
 clear_bullets(ps)
 clear_bullets(eb)
 for i=0,nal-1 do
  local a=new_alien()
  al[i]=a
  a.ty=i<4 and T_BOSS or i<20 and T_BUTTERFLY or T_BEE
  a.hp=(not challenge and a.ty==T_BOSS) and 2 or 1
  a.st=A_ENTER
  a.y=255
 end
 -- when each slot starts, and on which path (slot -1: an extra alien, not used)
 local w,h=a_w[row+1],a_rm[row*3+3]
 for k=1,#w,3 do
  local a=al[w[k+1]]
  if w[k+1]>=0 then
   a.dly,a.path=w[k],w[k+2]
   a.bflags=a_eb[w[k+1]+1]==1 and h or 0
   a.btmr=a_p[w[k+2]+1][3]
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
 stateTimer=107
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
  if dive then hold=6 end
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
 local k=a.pstep*2+4
 local p=a_p[a.path+1]
 a.x+=p[k]
 a.y+=p[k+1]
 a.pstep+=1
end

function path_launch(a)
 local p=a_p[a.path+1]
 a.ent=1
 a.pstep=0
 a.x,a.y=p[1],p[2]
end

-- the formation swings while the aliens fly in (+-32, a step every 4 arcade frames), then breathes
function arc_form_frame()
 ff+=1
 if breathe then
  if ff&3==0 then bstep=(bstep+1)&63 end
  return
 end
 if (ff-1)&3>0 then return end
 swayPos+=swayDir
 if entering==0 and swayPos==0 then
  breathe,bstep=true,0
 elseif swayPos>=32 then swayDir=-1
 elseif swayPos<=-32 then swayDir=1 end
 formDx=swayPos+td(swayPos*3,7)
end

function update_formation()
 local n=0
 for i=0,nal-1 do
  if al[i].st==A_ENTER then n+=1 end
 end
 entering=n
 if challenge then return end -- the arcade clock: 6 frames for every 5 ticks
 fclk+=6
 while fclk>=5 do
  fclk-=5
  arc_form_frame()
 end
end

-- one step of v towards t, n long
function toward(v,t,n)
 return v<t and n or v>t and -n or 0
end

function plen(a) -- steps of the path of an alien
 return (#a_p[a.path+1]-3)\2
end

function update_entry()
 for i=0,nal-1 do
  local a=al[i]
  if a.st==A_ENTER then
   if a.ent==0 then
    if state==S_PLAY then -- the waves wait while the ship is dead or taken
     a.dly-=1
     if a.dly<=0 then path_launch(a) end
    end
   elseif a.ent==1 then
    if a.pstep>=plen(a) then a.ent=2 else path_step(a) end
   else
    local tx,ty=slot_px(i),slot_py(i)
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
    if chalTimer>=a.dly then path_launch(a) end
   elseif a.pstep>=plen(a) then
    a.st=A_DEAD
   else
    path_step(a)
   end
  end
 end
end

function spawn_ebullet(a)
 local d=px-a.x
 for i=0,ebn-1 do
  local b=eb[i]
  if not b.act then
   b.act=true
   b.x=a.x
   b.y=a.y+8
   -- aimed at the ship: it falls (py - y) / 2.5 ticks, the speed is in 16ths of a pixel
   b.ax=0
   b.dx=mid(-24,td(16*d,(py-b.y)*2\5+1),24) -- at most 0.6 of the fall speed, as in the arcade
   return
  end
 end
end

function start_dive(i,capture,peel)
 local a=al[i]
 a.st=A_DIVE
 a.timer=peel
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
 -- the arcade path of its kind: boss or escort 2, butterfly 1, bee 0
 a.pstep,a.bflags,a.btmr=0,bombFlags,30
 a.dpath=capture and -1 or a_map[((a.esc>0 or a.ty==T_BOSS) and 2 or a.ty==T_BUTTERFLY and 1 or 0)*10+a_row[i+1]*2+a_side[i+1]+1]
end

function dive_step(i)
 local a=al[i]
 if not a.capdive then
  if a.timer>0 then -- an escort waits for its boss
   a.timer-=1
   a.x,a.y=slot_px(i),slot_py(i)
   return
  end
  local d=a.dpath>=0 and a_d[a.dpath+1]
  if d and a.pstep<(#d-1)\2 then
   a.x+=d[a.pstep*2+2]
   a.y+=d[a.pstep*2+3]
  else -- the end of the path of a butterfly: it aims at the ship
   a.y+=3
   if frame&1==1 then a.x+=toward(a.x,px,1) end
  end
  a.pstep+=1
  if a.y>=244 then -- gone: it comes back from the top when the arcade dive would end
   a.st=A_RETURN
   a.y=0
   a.timer=max(0,(d and d[1] or 220)-a.pstep-slot_py(i)\2)
  end
  return
 end
 if a.timer>0 then
  a.timer-=1
  a.x+=2*a.dir
  a.y+=1
  return
 end
 a.y+=3-(diff<5 and 1 or 0)
 if a.capdive or frame&1==1 then a.x+=toward(a.x,px,1) end
 if a.capdive and a.y>=196 then
  a.st=A_BEAM
  cap=C_BEAM
  beamLen,beamAcc=0,0
  beamTimer=180
  beamPh,beamStep=0,a_st[arc_sn()+6]*50\6\4
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
   a.x=slot_px(i)
   a.y=slot_py(i)
   if a.timer>0 then a.timer-=1 end -- just home: it turns round before it can dive again
  elseif st==A_EXPLODE then
   a.timer-=1
   if a.timer<0 then a.st=A_DEAD end
  elseif st==A_DIVE then
   dive_step(i)
  elseif st==A_RETURN then
   a.x=slot_px(i)
   if a.timer>0 then
    a.timer-=1
   else
    a.y+=2
    if a.y>=slot_py(i) then
     a.y=slot_py(i)
     a.st=A_FORM
     a.esc=0
     a.timer=a.ty==T_BEE and 3 or 45
    end
   end
  end
 end
end

-- the arcade's dive scheduler (psp/game.c arc_frame; one call is one arcade frame)
function arc_standby(from,to)
 for i=from,to-1 do
  if al[i].st==A_FORM and al[i].timer==0 then return i end
 end
 return -1
end

function arc_sortie_boss() -- who dives with whom
 local bfb={[0]=0,1,3,2,0}
 if cap==0 then
  wingm+=1
  if wingm&1==0 and not dual then -- every second sortie tries to capture
   local b=arc_standby(0,4)
   if b>=0 then start_dive(b,true,20) end
   return
  end
 end
 local c,slot,n,mb,mc=0,-1,1,0,0
 for k=1,6 do
  local e=al[a_wg[k]]
  c=(c<<1)|(e.st==A_FORM and e.timer==0 and 1 or 0)
 end
 for ixl=0,1 do
  local cc=c
  for b=4,1,-1 do
   local a,e=cc&7,al[bfb[b]]
   if slot<0 and (ixl==0 and a~=4 and a>=3 or ixl==1 and a~=0) and e.st==A_FORM and e.timer==0 then
    slot,n,mb,mc=bfb[b],2-ixl,b,cc
   end
   cc\=2
  end
 end
 if slot<0 then -- a boss alone
  slot=arc_standby(0,4)
  if slot>=0 then start_dive(slot,false,0) end
  return
 end
 local b,esc=mb+1,{}
 for k=1,n do
  local cy=mc&1
  mc=(mc\2)|(cy<<7)
  if cy==0 then
   b-=1
   cy=mc&1
   mc=(mc\2)|(cy<<7)
   if cy==0 then b-=1 end
  end
  if b>=0 and b<6 then add(esc,a_wg[b+1]) end
  b-=1
 end
 for e in all(esc) do al[e].esc=slot+1 end
 start_dive(slot,false,0)
 for k,e in pairs(esc) do start_dive(e,false,k) end
end

function arc_frame()
 local sn=arc_sn()
 local p0,p1,p2,p3,maxb,p5,p7=a_st[sn],a_st[sn+1],a_st[sn+2],a_st[sn+3],a_st[sn+4],a_st[sn+5],a_st[sn+7]
 local n,flying=0,0
 af+=1
 if af&31==0 then
  if tmr2>0 then tmr2-=1 end
  if hold>0 then hold-=1 end
 end
 local hdr0=a_rm[a_st[sn-1]*3+2]
 for i=0,nal-1 do
  local st=al[i].st
  if st~=A_DEAD and st~=A_EXPLODE then n+=1 end
  if st==A_DIVE or st==A_RETURN or st==A_BEAM then flying+=1 end
 end
 local tens=n\10
 if tmr2<60 then maxb=p5 end
 bombFlags=a_bt[4*p0+tens+1]
 local cont=n<p7
 local idx=(tmr2<40 and 1 or 0)+(tmr2==0 and 1 or 0)
 local rl={cont and 2 or a_bt[32+4*p1+tens+1],cont and 2 or a_rd[3*p2+idx+1],cont and 2 or a_be[3*p3+idx+1]}
 for i=0,nal-1 do -- bombs: a flyer drops one at every set bit of its flags, every hdr0 frames, high on the screen
  local a=al[i]
  if (a.st==A_DIVE and not a.capdive) or (a.st==A_ENTER and a.ent==1) then
   a.btmr-=1
   if a.btmr<=0 then
    a.btmr=hdr0
    if a.bflags&1==1 and a.y<=163 and hold==0 then spawn_ebullet(a) end
    a.bflags\=2
   end
  end
 end
 if entering>0 or af&15>0 then return end
 local i=0
 while i<3 do
  sortie[i]-=1
  if sortie[i]==0 then break end
  i+=1
 end
 if i==3 then return end
 if flying>=maxb then
  sortie[i]+=1
  return
 end
 sortie[i]=rl[i+1]
 if i==2 then
  n=arc_standby(20,40)
  if n>=0 then start_dive(n,false,0) end
 elseif i==1 then
  n=arc_standby(4,20)
  if n>=0 then start_dive(n,false,0) end
 else
  arc_sortie_boss()
 end
end

function select_dive()
 if challenge then return end
 clk+=6
 while clk>=5 do
  clk-=5
  arc_frame()
 end
end

function update_ebullets()
 for i=0,ebn-1 do
  local b=eb[i]
  if b.act then
   b.y+=2+(frame&1)
   b.ax+=b.dx
   b.x+=b.ax\16
   b.ax&=15
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
 for i=0,ebn-1 do
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
  if beamPh==0 then
   beamAcc+=1
   if beamAcc>=beamStep then
    beamAcc=0
    beamLen+=1
    if beamLen>=4 then beamPh,beamTimer=1,53 end
   end
  elseif beamPh==2 then
   beamAcc+=1
   if beamAcc>=beamStep then
    beamAcc=0
    beamLen-=1
    if beamLen<=0 then
     cap=C_NONE
     b.st=A_RETURN
     b.y=0
    end
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
    beamPh,beamAcc=2,0
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
    stateTimer=80
   end
  end
 elseif st==S_READY then
  if challenge then update_aliens() else move_world() end
  if not challenge then -- the ship comes back when nothing flies any more: the divers finish first, the beam too
   local flying=0
   update_capture()
   for k=0,nal-1 do
    local a=al[k]
    if a.st==A_DIVE or a.st==A_RETURN or a.st==A_BEAM or (a.st==A_ENTER and a.ent>0) then flying+=1 end
   end
   if flying>0 then return end
  end
  stateTimer-=1
  if stateTimer<=0 then
   state=S_PLAY
   px=160
   invuln=120
   tmr2=min(120,tmr2+30) -- after a death the sorties start slowly again
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
