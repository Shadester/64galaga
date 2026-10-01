import re,sys
from PIL import Image
src=open('art.h').read()
pal={'y':(255,220,60),'Y':(200,140,20),'c':(80,230,255),'w':(255,255,255),'k':(25,25,50),'o':(255,140,30),'r':(255,60,60),'b':(60,110,255),'g':(170,170,190)}
var={'bee':((70,130,255),(150,200,255),(30,60,190)),'bfly':((255,60,60),(255,150,130),(160,20,40)),'boss':((60,220,90),(170,255,160),(20,130,50)),'bossp':((170,80,255),(215,165,255),(100,40,170))}
sp=re.findall(r'art_(\w+) = \{(.*?)\};',src,re.S)
imgs=[]
for name,body in sp:
    rows=re.findall(r'"([^"]*)"',body)
    assert len(rows)==16,(name,len(rows))
    for r in rows: assert len(r)==8,(name,r)
    k=name.split('_')[0]; vs=[k] if k in var else ['']
    if k=='boss': vs=['boss','bossp']
    for v in vs:
        im=Image.new('RGBA',(16,16),(10,10,30,255))
        for y,r in enumerate(rows):
            full=r+r[::-1]
            for x,ch in enumerate(full):
                if ch=='.':continue
                if ch in 'mMn': c=var[v]['mMn'.index(ch)] if v else (255,0,255)
                else: c=pal[ch]
                im.putpixel((x,y),c+(255,))
        imgs.append(im)
W=Image.new('RGBA',(len(imgs)*18*4,16*4+8),(10,10,30,255))
for i,im in enumerate(imgs): W.paste(im.resize((64,64),Image.NEAREST),(i*72+4,4))
W.save(sys.argv[1])
