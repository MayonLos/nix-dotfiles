#!/usr/bin/env python3
"""Generate a tiny synthetic corpus for seek tests; never reads home-directory data."""
from __future__ import annotations

import json
import random
import sys
import zipfile
from pathlib import Path


def put_zip(path: Path, parts: dict[str, str]) -> None:
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, content in parts.items():
            archive.writestr(name, content)


def make_pdf(path: Path) -> None:
    # Minimal two-page PDF with ASCII searchable fixture text.
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 7 0 R >> >> /Contents 4 0 R >>",
        b"<< /Length 61 >>\nstream\nBT /F1 18 Tf 72 700 Td (Thermodynamics entropy lecture) Tj ET\nendstream",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 7 0 R >> >> /Contents 6 0 R >>",
        b"<< /Length 61 >>\nstream\nBT /F1 18 Tf 72 700 Td (Fourier heat equation boundary) Tj ET\nendstream",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ]
    data = bytearray(b"%PDF-1.4\n")
    offsets = [0]
    for number, body in enumerate(objects, 1):
        offsets.append(len(data))
        data.extend(f"{number} 0 obj\n".encode() + body + b"\nendobj\n")
    xref = len(data)
    data.extend(f"xref\n0 {len(offsets)}\n0000000000 65535 f \n".encode())
    for offset in offsets[1:]:
        data.extend(f"{offset:010d} 00000 n \n".encode())
    data.extend(f"trailer\n<< /Size {len(offsets)} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode())
    path.write_bytes(data)


def generate(root: Path) -> None:
    root.mkdir(parents=True, exist_ok=True)
    (root / "linear-algebra.md").write_text(
        "# 线性代数复习\n\n特征值 eigenvalue 决定线性变换的伸缩方向。\n矩阵秩 rank 表示列空间维数。\n正交投影 orthogonal projection 最小化平方误差。\n", encoding="utf-8")
    (root / "networking.md").write_text(
        "# Computer Networks\n\nTCP provides reliable ordered byte streams.\nDNS maps a domain name to an IP address.\nThe congestion window limits in-flight data.\n", encoding="utf-8")
    (root / "solver.py").write_text(
        '"""Synthetic numerical methods notes."""\n\ndef newton_step(x, f, derivative):\n    """Newton iteration updates x using the local tangent."""\n    return x - f(x) / derivative(x)\n\n# Euler method has global error proportional to the step size.\n', encoding="utf-8")
    (root / "thermodynamics.pdf").write_bytes(b"")
    make_pdf(root / "thermodynamics.pdf")

    docx = """<?xml version="1.0" encoding="UTF-8"?>
<w:document xmlns:w="urn:w"><w:body><w:p><w:r><w:t>数据库事务隔离与可重复读</w:t></w:r></w:p><w:p><w:r><w:t>ACID includes atomicity consistency isolation durability.</w:t></w:r></w:p><w:p><w:r><w:t>MVCC keeps multiple row versions for concurrent readers.</w:t></w:r></w:p></w:body></w:document>"""
    put_zip(root / "database.docx", {"word/document.xml": docx})

    pptx = """<?xml version="1.0" encoding="UTF-8"?>
<p:sld xmlns:p="urn:p" xmlns:a="urn:a"><p:cSld><a:t>概率论中心极限定理</a:t><a:t>Independent variables converge toward a normal distribution.</a:t></p:cSld></p:sld>"""
    put_zip(root / "probability.pptx", {
        "ppt/presentation.xml": "<p:presentation xmlns:p='urn:p' xmlns:r='urn:r'><p:sldIdLst><p:sldId id='1' r:id='rId1'/></p:sldIdLst></p:presentation>",
        "ppt/_rels/presentation.xml.rels": "<Relationships><Relationship Id='rId1' Target='slides/slide1.xml' Type='slide'/></Relationships>",
        "ppt/slides/slide1.xml": pptx,
    })

    workbook = """<?xml version="1.0"?><workbook xmlns="urn:s"><sheets><sheet name="Physics" sheetId="1" r:id="r1"/></sheets></workbook>"""
    worksheet = """<?xml version="1.0"?><worksheet xmlns="urn:s"><sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>光电效应</t></is></c></row><row r="2"><c r="A2" t="inlineStr"><is><t>Photon energy equals Planck constant times frequency.</t></is></c></row><row r="3"><c r="A3" t="inlineStr"><is><t>Threshold frequency determines electron emission.</t></is></c></row></sheetData></worksheet>"""
    put_zip(root / "physics.xlsx", {
        "xl/workbook.xml": workbook,
        "xl/_rels/workbook.xml.rels": "<Relationships><Relationship Id='r1' Target='worksheets/sheet1.xml' Type='sheet'/></Relationships>",
        "xl/worksheets/sheet1.xml": worksheet,
    })

    # Distractors are generic synthetic course notes. The fixed seed keeps the
    # retrieval benchmark reproducible without introducing any personal data.
    rng = random.Random(5001)
    topics = ["Campus Services", "Field Methods", "Study Skills", "Research Design", "Laboratory Safety"]
    words = ["schedule", "method", "sample", "record", "review", "process", "report", "system", "measure", "result", "summary", "section", "course", "practice", "project", "group", "concept", "reference", "resource", "standard"]
    for index in range(1, 101):
        topic = topics[(index - 1) % len(topics)]
        sentences = []
        for _ in range(5):
            sentence = " ".join(rng.sample(words, 7)).capitalize() + "."
            sentences.append(sentence)
        (root / f"distractor-{index:03}.md").write_text(
            f"# {topic} Memo {index:03}\n\n" + "\n".join(sentences) + "\n",
            encoding="utf-8",
        )

    cases = [
        ("Which quantity gives a linear map's stretch directions?", "linear-algebra.md"),
        ("矩阵的秩代表什么空间维数？", "linear-algebra.md"),
        ("What does orthogonal projection minimize?", "linear-algebra.md"),
        ("特征值的英文是什么？", "linear-algebra.md"),
        ("Which protocol provides an ordered reliable byte stream?", "networking.md"),
        ("DNS 将域名解析成什么？", "networking.md"),
        ("What limits the amount of in flight TCP data?", "networking.md"),
        ("牛顿迭代的实现在哪个源文件？", "solver.py"),
        ("What does a Newton step use from the local tangent?", "solver.py"),
        ("Euler 方法的全局误差与什么成正比？", "solver.py"),
        ("哪份讲义提到了 Fourier heat equation？", "thermodynamics.pdf"),
        ("Which lecture page mentions entropy?", "thermodynamics.pdf"),
        ("事务 ACID 的四个属性有哪些？", "database.docx"),
        ("Which mechanism keeps multiple row versions for readers?", "database.docx"),
        ("Where is 可重复读 mentioned?", "database.docx"),
        ("什么定理说明独立变量趋向正态分布？", "probability.pptx"),
        ("Which slides discuss independent variables and normal distribution?", "probability.pptx"),
        ("光子能量等于普朗克常数乘以什么？", "physics.xlsx"),
        ("What determines electron emission in the photoelectric effect?", "physics.xlsx"),
        ("Which spreadsheet contains 光电效应?", "physics.xlsx"),
    ]
    (root / "benchmark.json").write_text(
        json.dumps([{"question": q, "expected": name} for q, name in cases], ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    generate(Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).parent / "corpus")
