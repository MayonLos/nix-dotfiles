#!/usr/bin/env python3
"""Build the embedded, exam-tagged SQLite subset from ECDICT CSV."""
import argparse
import csv
import sqlite3

BOOKS = {
    "cet4": "CET-4", "cet6": "CET-6", "ky": "考研",
    "ielts": "IELTS", "toefl": "TOEFL", "gre": "GRE",
}


def clean(value):
    # ECDICT stores multi-line translation strings as literal backslash-n.
    return (value or "").replace(r"\n", "\n").strip()


def format_exchange(value):
    """Present ECDICT inflection/lemma metadata; this is not etymological roots."""
    labels = {
        "p": "过去式", "d": "过去分词", "i": "现在分词", "3": "第三人称单数",
        "r": "比较级", "t": "最高级", "s": "复数", "0": "原形", "1": "原形变体",
    }
    forms = []
    for part in (value or "").split("/"):
        kind, separator, word = part.partition(":")
        if separator and word.strip() and kind in labels:
            forms.append(f"{labels[kind]} {word.strip()}")
    return "；".join(forms)


def make_database(source, destination):
    db = sqlite3.connect(destination)
    db.executescript("""
      PRAGMA journal_mode=OFF;
      PRAGMA synchronous=OFF;
      DROP TABLE IF EXISTS words;
      CREATE TABLE words (
        word TEXT NOT NULL COLLATE NOCASE,
        phonetic TEXT NOT NULL DEFAULT '',
        meaning TEXT NOT NULL DEFAULT '',
        definition TEXT NOT NULL DEFAULT '',
        example TEXT NOT NULL DEFAULT '',
        roots TEXT NOT NULL DEFAULT '',
        book TEXT NOT NULL,
        frequency INTEGER,
        PRIMARY KEY (word, book)
      );
      CREATE INDEX words_by_book_frequency ON words(book, frequency DESC);
      CREATE INDEX words_by_frequency ON words(frequency);
    """)
    insert = "INSERT OR REPLACE INTO words VALUES (?, ?, ?, ?, '', ?, ?, ?)"
    with open(source, newline="", encoding="utf-8-sig") as handle:
        for row in csv.DictReader(handle):
            word = (row.get("word") or "").strip()
            if not word:
                continue
            tags = sorted(set((row.get("tag") or "").lower().split()))
            books = [tag for tag in tags if tag in BOOKS]
            if not books:
                continue
            raw_frequency = row.get("frq") or row.get("bnc") or ""
            try:
                rank = int(raw_frequency) if raw_frequency else None
                if rank == 0:
                    rank = None
                # ECDICT stores rank 1 as most frequent. Negating the rank
                # makes a descending SQL order put common words first.
                frequency = -rank if rank is not None else None
            except ValueError:
                frequency = None
            for book in books:
                db.execute(insert, (word, row.get("phonetic", ""), clean(row.get("translation")),
                                    clean(row.get("definition")), format_exchange(row.get("exchange")), book, frequency))
    db.commit()
    db.execute("ANALYZE")
    count = db.execute("SELECT count(*) FROM words").fetchone()[0]
    db.close()
    return count


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("source", help="ECDICT ecdict.csv")
    parser.add_argument("destination", help="output SQLite file")
    args = parser.parse_args()
    print(f"Wrote {make_database(args.source, args.destination)} exam-tagged words")


if __name__ == "__main__":
    main()
