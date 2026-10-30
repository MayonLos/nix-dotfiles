#!/usr/bin/env python3
"""Generate the deterministic, synthetic photo fixture used by PhotoFlowTest."""
import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

WIDTH, HEIGHT = 1440, 900
FONT = Path("/nix/store/zsqnqrsvryxsa5xhy44y9szvqcmd9628-source-han-sans-2.005/share/fonts/opentype/source-han-sans/SourceHanSans.ttc")
DAYS = ["周一", "周二", "周三", "周四", "周五"]
ROWS = ["第1节", "第2节", "第3节"]
FIELDS = ["高等数学", "教师：王老师", "教室：A203", "周次：1-16周(单)"]


def make(out: Path) -> None:
    if not FONT.is_file():
        raise SystemExit(f"Chinese fixture font unavailable: {FONT}")
    out.parent.mkdir(parents=True, exist_ok=True)
    image = Image.new("RGB", (WIDTH, HEIGHT), (250, 250, 247))
    draw = ImageDraw.Draw(image)
    header_font = ImageFont.truetype(str(FONT), 38)
    period_font = ImageFont.truetype(str(FONT), 34)
    title_font = ImageFont.truetype(str(FONT), 40)
    field_font = ImageFont.truetype(str(FONT), 32)

    left, label_width, day_width = 100, 130, 238
    top, header_height, row_height = 100, 70, 200
    right, bottom = left + label_width + len(DAYS) * day_width, top + header_height + len(ROWS) * row_height
    grid = (156, 166, 172)
    draw.rounded_rectangle((24, 24, WIDTH - 24, HEIGHT - 24), radius=18, fill=(250, 250, 247), outline=(194, 199, 202), width=2)

    # Header cells and the three body rows. All text remains at least 24 px high.
    for x in [left, left + label_width] + [left + label_width + i * day_width for i in range(1, len(DAYS) + 1)]:
        draw.line((x, top, x, bottom), fill=grid, width=2)
    for y in [top, top + header_height] + [top + header_height + i * row_height for i in range(1, len(ROWS) + 1)]:
        draw.line((left, y, right, y), fill=grid, width=2)
    draw.rectangle((left, top, left + label_width, top + header_height), fill=(222, 230, 234))
    for day_index, day in enumerate(DAYS):
        x0 = left + label_width + day_index * day_width
        draw.rectangle((x0, top, x0 + day_width, top + header_height), fill=(222, 230, 234))
        draw.line((x0, top, x0, bottom), fill=grid, width=2)
        draw.text((x0 + (day_width - draw.textbbox((0, 0), day, font=header_font)[2]) / 2, top + 12), day, font=header_font, fill=(42, 52, 62))
    draw.line((right, top, right, bottom), fill=grid, width=2)
    draw.text((left + 18, top + 15), "节次", font=header_font, fill=(42, 52, 62))
    for row_index, label in enumerate(ROWS):
        y0 = top + header_height + row_index * row_height
        draw.text((left + 15, y0 + 72), label, font=period_font, fill=(42, 52, 62))

    # One rich cell at Wednesday / period 2. Truth is stored beside this fixture.
    cell_left = left + label_width + 2 * day_width
    cell_center = cell_left + day_width / 2
    field_tops = [384, 430, 474, 518]
    for index, (text, font, y) in enumerate(zip(FIELDS, [title_font, field_font, field_font, field_font], field_tops)):
        bounds = draw.textbbox((0, 0), text, font=font)
        x = cell_center - (bounds[2] - bounds[0]) / 2
        draw.text((x, y), text, font=font, fill=(32, 42, 52))

    image.save(out, format="PNG", optimize=False)
    truth = {
        "schema": "synthetic-timetable-photo-v1",
        "seed": 20261030,
        "image": out.name,
        "width": WIDTH,
        "height": HEIGHT,
        "occupiedCells": [{
            "weekday": 3,
            "periodStart": 2,
            "periodEnd": 2,
            "courseName": "高等数学",
            "teacher": "王老师",
            "classroom": "A203",
            "weeks": "1-16周(单)",
            "lines": FIELDS,
        }],
        "weekdayHeaders": DAYS,
        "periodHeaders": ROWS,
        "font": str(FONT),
        "notes": "程序合成印刷体课表；无真实用户数据；所有文字字号至少 32 px。",
    }
    out.with_suffix(".truth.json").write_text(json.dumps(truth, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"generated {out} ({WIDTH}x{HEIGHT}), 1 occupied cell; truth={out.with_suffix('.truth.json')}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, default=Path(__file__).resolve().parents[1] / "app/src/androidTest/assets/synthetic-photo.png")
    args = parser.parse_args()
    make(args.out)


if __name__ == "__main__":
    main()
