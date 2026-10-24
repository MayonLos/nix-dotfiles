"""Astra compositions, with user-requested brighter gradients and blue/cyan glow.

Only palette inputs supply colors. SVG is rendered at 2x by librsvg; the final
sRGB raster receives seeded monochrome LCG noise after Lanczos reduction.
"""
import json
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, PngImagePlugin

palette = json.loads(Path(sys.argv[1]).read_text())
out = Path(sys.argv[2])
out.mkdir(parents=True, exist_ok=True)


def stop(at, color, alpha=1):
    return f'<stop offset="{at}%" stop-color="{palette[color]}" stop-opacity="{alpha}"/>'


def linear(name, coords, stops):
    x1, y1, x2, y2 = coords
    return f'<linearGradient id="{name}" gradientUnits="userSpaceOnUse" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}">' + ''.join(stop(*s) for s in stops) + '</linearGradient>'


def radial(name, x, y, rx, ry, strength):
    return f'<radialGradient id="{name}" gradientUnits="userSpaceOnUse" gradientTransform="translate({x} {y}) scale({rx} {ry})" cx="0" cy="0" r="1">' + stop(0, 'blue', strength) + stop(48, 'cyan', strength * .55) + stop(100, 'cyan', 0) + '</radialGradient>'


def path(d, fill, opacity=1, stroke=None):
    edge = '' if stroke is None else f' stroke="{palette[stroke]}" stroke-width="1.2"'
    return f'<path d="{d}" fill="{fill}" opacity="{opacity}"{edge}/>'


bay = 'M -180 1540 C 480 1430 790 1580 1390 1180 C 1910 830 2150 740 2760 840 L 2760 1800 L -180 1800 Z'
bay2 = 'M 180 1740 C 900 1430 1090 1490 1610 1190 C 2060 930 2390 1070 2740 1080 L 2740 1800 Z'
bay3 = 'M 740 1740 C 1250 1450 1600 1550 1940 1330 C 2290 1110 2530 1290 2770 1250 L 2770 1800 Z'
strata = 'M -80 1130 C 380 1190 760 760 1190 900 C 1570 1020 1770 580 2160 660 C 2390 700 2490 540 2660 570 L 2660 1680 L -80 1680 Z'
strata2 = 'M -80 1370 C 410 1210 640 1180 1010 1240 C 1450 1320 1870 850 2230 980 C 2410 1040 2540 840 2660 890 L 2660 1680 L -80 1680 Z'
strata3 = 'M -80 1550 C 460 1290 690 1500 1170 1400 C 1600 1300 1980 1310 2660 1130 L 2660 1680 L -80 1680 Z'

for i, (name, amplitude) in enumerate([('01-quiet-bay', 1), ('02-strata', 1.4), ('03-orbit', .8), ('04-night-paper', 1.6)]):
    defs = linear('base', (0, 0, 2560, 1600), [(0, 'deep'), (45, 'bg'), (100, 'selection')])
    defs += linear('ridge', (700, 600, 2400, 1650), [(0, 'selection'), (50, 'surface'), (100, 'deep')])
    defs += linear('front', (1200, 950, 2560, 1680), [(0, 'surface'), (100, 'deep')])
    # Stronger than the design-stage .09: requested visible but soft light.
    defs += radial('glow', 2180, 1180, 1550, 1050, .24 if i != 3 else .13)
    defs += radial('soft', 850, 1180, 1400, 850, .09)
    shapes = '<rect width="2560" height="1600" fill="url(#base)"/>'
    if i == 0:
        shapes += path(bay, 'url(#ridge)', .78) + path(bay2, 'url(#front)', .88) + path(bay3, palette['deep'], .94)
        shapes += path(bay.split(' L ')[0], 'none', .30, 'border')
    elif i == 1:
        shapes += path(strata, 'url(#ridge)', .85) + path(strata, palette['cyan'], .05)
        shapes += path(strata2, 'url(#front)', .94) + path(strata3, palette['deep'])
        shapes += path(strata.split(' L ')[0], 'none', .24, 'border')
    elif i == 2:
        for r, alpha, color in [(1000, .24, 'border'), (850, .18, 'border'), (700, .14, 'blue')]:
            shapes += f'<circle cx="2300" cy="1130" r="{r}" fill="none" stroke="{palette[color]}" stroke-opacity="{alpha}" stroke-width="1.4"/>'
        shapes += f'<circle cx="2300" cy="1130" r="560" fill="{palette["surface"]}" opacity=".36"/>'
    else:
        shapes += '<polygon points="0,1000 1700,0 2200,0 0,1320" fill="url(#ridge)" opacity=".34"/>'
        shapes += f'<polygon points="480,1600 2560,370 2560,720 1100,1600" fill="{palette["deep"]}" opacity=".20"/>'
        for k in range(8):
            shapes += f'<path d="M {-500+480*k} 1600 L {500+480*k} 0" stroke="{palette["border"]}" stroke-opacity=".045"/>'
    shapes += '<rect width="2560" height="1600" fill="url(#glow)"/><rect width="2560" height="1600" fill="url(#soft)"/>'
    svg = out / f'{name}.svg'
    svg.write_text('<svg xmlns="http://www.w3.org/2000/svg" width="2560" height="1600" viewBox="0 0 2560 1600" color-interpolation="sRGB"><defs>' + defs + '</defs>' + shapes + '</svg>')
    raw = out / f'{name}-raw.png'
    target = out / f'{name}.png'
    subprocess.run(['rsvg-convert', '-w', '5120', '-h', '3200', '-o', str(raw), str(svg)], check=True)
    subprocess.run(['magick', str(raw), '-filter', 'Lanczos', '-resize', '2560x1600!', '-colorspace', 'sRGB', '-depth', '8', str(target)], check=True)
    pixels = np.asarray(Image.open(target).convert('RGB')).astype(np.float64)
    noise = np.empty(2560 * 1600, dtype=np.float64)
    state = 241024 + i
    for j in range(noise.size):
        state = (1664525 * state + 1013904223) & 0xffffffff
        noise[j] = amplitude * (2 * state / 4294967295 - 1)
    pixels = np.rint(np.clip(pixels + noise.reshape(1600, 2560, 1), 0, 255)).astype(np.uint8)
    png_info = PngImagePlugin.PngInfo()
    png_info.add(b"sRGB", b"\x00")
    Image.fromarray(pixels).save(target, pnginfo=png_info)
    raw.unlink()
    svg.unlink()
