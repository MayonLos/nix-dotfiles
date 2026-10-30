#!/usr/bin/env python3
"""Build an evidence gallery from real emulator PNGs, preserving original screenshots."""
import argparse
import html
from pathlib import Path
from PIL import Image, ImageDraw

parser = argparse.ArgumentParser()
parser.add_argument('--shots', type=Path, required=True)
args = parser.parse_args()
shots = args.shots
paths = sorted(shots.glob('round*/*.png'))
assert paths, 'No actual emulator screenshot rounds found'
items = []
for path in paths:
    with Image.open(path) as im:
        assert im.size == (1080, 2400), (path, im.size)
    rel = path.relative_to(shots)
    items.append(f'<figure><a href="{html.escape(str(rel))}"><img loading="lazy" src="{html.escape(str(rel))}"></a><figcaption>{html.escape(path.stem)}</figcaption></figure>')
(shots / 'gallery.html').write_text('''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>课表 · Android 运行截图</title><style>body{background:#1e2228;color:#d7dae0;font:16px system-ui;margin:24px}main{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:20px}figure{margin:0;background:#272c33;padding:12px;border-radius:12px}img{width:100%;height:auto}figcaption{padding:8px 0;word-break:break-word}a{color:#98c379}</style><h1>课表 · Android 运行截图</h1><p>API 35 AOSP，无 GMS；1080 × 2400。所有课表均为合成数据。round1 为复核中间版本，round2 为修正后回归。小组件页为 debug AppWidgetHost 中的真实 Glance RemoteViews；通知页为 AOSP 系统界面。OPPO 桌面仍待实机验收。点击查看原始截图。</p><main>''' + ''.join(items) + '</main></html>', encoding='utf-8')
latest = [p for p in paths if p.parent.name == 'round2'] or paths
columns = 6
width, height = 216, 480
rows = (len(latest) + columns - 1) // columns
canvas = Image.new('RGB', (columns * (width + 20) + 20, rows * (height + 48) + 20), '#1e2228')
draw = ImageDraw.Draw(canvas)
for index, path in enumerate(latest):
    x = 20 + index % columns * (width + 20)
    y = 20 + index // columns * (height + 48)
    with Image.open(path) as im:
        canvas.paste(im.convert('RGB').resize((width, height)), (x, y))
    draw.text((x, y + height + 8), path.stem.replace('round2-', ''), fill='#d7dae0')
canvas.save(shots / 'overview.png')
print(f'{len(paths)} screenshots; overview uses {len(latest)} final screenshots')
