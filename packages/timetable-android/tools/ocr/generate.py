#!/usr/bin/env python3
"""Create deterministic synthetic timetable images and cell-level truth labels."""
import argparse, json, random
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageEnhance

WORDS = ["高等数学", "大学英语", "数据结构", "线性代数", "计算机网络", "操作系统", "概率统计", "电路原理", "离散数学", "软件工程", "大学物理", "马克思原理"]
DAYS = ["周一", "周二", "周三", "周四", "周五"]
FONTS = [
    "/nix/store/zsqnqrsvryxsa5xhy44y9szvqcmd9628-source-han-sans-2.005/share/fonts/opentype/source-han-sans/SourceHanSans.ttc",
    "/nix/store/chv9apwmlhkm68jj8r9iwkwqllvvrc1h-source-han-serif-2.003/share/fonts/opentype/source-han-serif/SourceHanSerif.ttc",
    "/nix/store/846asrsxs0gb0kqq9jawgin9vp96nwbi-MapleMono-NF-CN-7.9/share/fonts/truetype/MapleMono-NF-CN-Regular.ttf",
]
STYLES = [
    ((250,250,247),(90,105,120),(214,224,232)),
    ((247,249,252),(58,91,127),(222,234,246)),
    ((255,250,243),(111,93,63),(240,229,210)),
]
W,H=1440,1000
LEFT,TOP,CW,RH=90,150,220,112


def make_one(i, out):
    rng=random.Random(20261030+i)
    bg,ink,head=STYLES[i%len(STYLES)]
    im=Image.new('RGB',(W,H),(238,238,235)); d=ImageDraw.Draw(im)
    fontfile=FONTS[i%len(FONTS)]
    ftitle=ImageFont.truetype(fontfile,32); fhead=ImageFont.truetype(fontfile,24)
    fcell=ImageFont.truetype(fontfile,23 if i%4 else 19)
    d.rounded_rectangle((28,24,W-28,H-24),radius=20,fill=bg,outline=(190,194,194),width=2)
    d.text((LEFT,48), ["2026-2027 秋季课程表","本科教学安排 · 第 1-16 周","我的课表 | 教学周视图"][i%3],font=ftitle,fill=ink)
    # 6 columns (row labels + five weekdays), 7 header/body rows
    for c in range(6):
        for r in range(7):
            x0=LEFT+c*CW; y0=TOP+r*RH
            x1=x0+CW; y1=y0+RH
            fill=head if r==0 or c==0 else bg
            d.rectangle((x0,y0,x1,y1),fill=fill,outline=(157,166,172),width=2 if i%3 else 1)
            if r==0 and c==0: txt="节次"
            elif r==0: txt=DAYS[c-1]
            elif c==0: txt=f"第{r}节"
            else: txt=""
            if txt: d.text((x0+12,y0+12),txt,font=fhead,fill=ink)
    occupied=[]; rich_fields=[]; merge_cells=[]
    is_rich=(i%6==0)
    rich_positions={(1,1),(2,3),(5,4)}
    if is_rich:
        # Remove the internal horizontal rule to form a two-period merged class.
        mx=LEFT+4*CW; my=TOP+3*RH
        d.rectangle((mx+2,my-2,mx+CW-2,my+2),fill=bg)
    for p in range(1,7):
        for day in range(1,6):
            force_rich=is_rich and (day,p) in rich_positions
            is_merge=is_rich and day==4 and p in (2,3)
            if is_merge:
                continue
            if force_rich or ((day*7+p*3+i)%4 != 0 and (day+p+i)%3 != 0):
                word=WORDS[(day*3+p+i)%len(WORDS)]
                fields={"course":word}
                lines=[word]
                if force_rich:
                    fields.update({"teacher":"教师:王老师","room":f"教室:A{301+(i%5)*10+day}","weeks":"1-16周(单)"})
                    lines=[fields["course"],fields["teacher"],fields["room"],fields["weeks"]]
                expected="".join(lines)
                cell={"day":day,"period":p,"text":expected,"fields":fields}
                occupied.append(cell)
                x=LEFT+day*CW; y=TOP+p*RH
                ftext=ImageFont.truetype(fontfile,18 if force_rich else (23 if i%4 else 19))
                line_h=24 if force_rich else 30; total_h=len(lines)*line_h
                y0=y+(RH-total_h)//2
                for line_no,line in enumerate(lines):
                    box=d.textbbox((0,0),line,font=ftext); tw=box[2]-box[0]; th=box[3]-box[1]
                    tx=x+(CW-tw)//2; ty=y0+line_no*line_h
                    d.text((tx,ty),line,font=ftext,fill=(32,45,55))
                    if force_rich:
                        rich_fields.append({"day":day,"period":p,"field":list(fields.keys())[line_no],"expected":line})
                    if line_no==0:
                        cell["box"]=[[tx,ty],[tx+tw,ty],[tx+tw,ty+th],[tx,ty+th]]
    if is_rich:
        day,p=4,2; word=WORDS[(day*3+p+i)%len(WORDS)]
        x=LEFT+day*CW; y=TOP+p*RH; merged_text=word
        ftext=ImageFont.truetype(fontfile,22); box=d.textbbox((0,0),merged_text,font=ftext)
        tw=box[2]-box[0]; th=box[3]-box[1]; tx=x+(CW-tw)//2; ty=y+RH-th
        d.text((tx,ty),merged_text,font=ftext,fill=(32,45,55))
        mbox=[[tx,ty],[tx+tw,ty],[tx+tw,ty+th],[tx,ty+th]]
        for period in (2,3):
            occupied.append({"day":day,"period":period,"text":merged_text,"fields":{"course":merged_text},"mergeId":f"merge-{i+1}","box":mbox})
        merge_cells.append({"day":day,"startPeriod":2,"endPeriod":3,"text":merged_text,"box":[x,y,x+CW,y+2*RH]})
    # Mutate the complete rendered sheet into varied screenshot/photo conditions.
    augmentations=[]
    if i%5==1:
        augmentations.append("low-contrast")
        im=ImageEnhance.Contrast(im).enhance(.76)
    if i%5==2:
        augmentations.append("gaussian-blur")
        im=im.filter(ImageFilter.GaussianBlur(.65))
    homography=None
    if i%5==3:
        augmentations.append("perspective-tilt")
        # mild perspective from an off-axis phone photo, retaining known projective transform
        import cv2, numpy as np
        arr=np.array(im)
        src=np.float32([[0,0],[W-1,0],[W-1,H-1],[0,H-1]])
        dx=(i%3-1)*22; dy=(i%4-2)*12
        dst=np.float32([[0+dx,0+dy],[W-1-dx,12-dy],[W-1,H-1-dy],[12,H-1+dy]])
        mat=cv2.getPerspectiveTransform(src,dst)
        homography=mat.tolist()
        arr=cv2.warpPerspective(arr,mat,(W,H),borderValue=(224,224,220))
        im=Image.fromarray(arr)
    if i%5==4:
        augmentations.append("low-resolution")
        # low-resolution screenshot/photo, resized back for detector input
        im=im.resize((640,450),Image.Resampling.LANCZOS).resize((W,H),Image.Resampling.BILINEAR)
    if homography:
        import cv2, numpy as np
        mat=np.array(homography,dtype="float32")
        for cell in occupied:
            cell["box"]=cv2.perspectiveTransform(np.array([cell["box"]],dtype="float32"),mat)[0].round(2).tolist()
    if i%7==6:
        augmentations.append("diagonal-shadow")
        # angled shadow over part of the sheet
        overlay=Image.new('RGBA',im.size,(0,0,0,0)); od=ImageDraw.Draw(overlay)
        od.polygon([(0,0),(420,0),(780,H),(350,H)],fill=(20,25,30,40))
        im=Image.alpha_composite(im.convert('RGBA'),overlay).convert('RGB')
    path=out/f"sheet-{i+1:02}.png"; im.save(path)
    return {"image":path.name,"width":W,"height":H,"grid":{"left":LEFT,"top":TOP,"cellWidth":CW,"cellHeight":RH,"days":5,"periods":6},"font":fontfile,"style":i%3,"transform":augmentations or ["clean"],"homography":homography,"occupied":occupied,"emptyCells":30-len(occupied),"richFields":rich_fields,"mergeCells":merge_cells}


def main():
    p=argparse.ArgumentParser(); p.add_argument('--out',required=True); p.add_argument('--count',type=int,default=30); a=p.parse_args()
    out=Path(a.out); out.mkdir(parents=True,exist_ok=True)
    labels=[make_one(i,out) for i in range(a.count)]
    (out/'truth.json').write_text(json.dumps({"schema":"synthetic-timetable-v1","seed":20261030,"samples":labels},ensure_ascii=False,indent=2),encoding='utf-8')
    print(f"generated {len(labels)} images, {sum(len(x['occupied']) for x in labels)} occupied and {sum(x['emptyCells'] for x in labels)} empty cells")
if __name__=='__main__': main()
