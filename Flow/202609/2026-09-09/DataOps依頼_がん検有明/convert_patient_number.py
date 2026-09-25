#!/usr/bin/env python3
"""がん研有明 DPC データ識別番号の復号（末尾0除去 → 先頭0埋め）。

匿名化: 診療系ID 0007925233 → DPC 0079252330（先頭0削除 + 末尾0追加）
復号:   DPC 0079252330 → 診療系ID 0007925233（末尾0除去 + 元桁数まで0埋め）

様式1 (FF1) / Dファイルとも、施設コードの次列（2列目）がデータ識別番号、という前提。
"""

from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path

ENCODINGS = ("cp932", "utf-8-sig", "utf-8")


def decode_dpc_patient_id(value: str) -> tuple[str, bool]:
    s = value.strip().strip('"')
    if not s:
        return s, False
    if s.endswith("0") and len(s) >= 2:
        return s[:-1].zfill(len(s)), True
    return s, False


def detect_encoding(path: Path) -> str:
    raw = path.read_bytes()
    for enc in ENCODINGS:
        try:
            raw.decode(enc)
            return enc
        except UnicodeDecodeError:
            continue
    return "cp932"


def detect_dialect(sample: str) -> csv.Dialect:
    try:
        return csv.Sniffer().sniff(sample, delimiters=",\t|")
    except csv.Error:
        dialect = csv.excel
        dialect.delimiter = ","
        return dialect


def convert_file(src: Path, dest: Path, id_col: int, dry_run: bool) -> dict:
    encoding = detect_encoding(src)
    text = src.read_text(encoding=encoding, errors="replace")
    lines = text.splitlines(keepends=True)
    if not lines:
        raise ValueError(f"empty file: {src}")

    sample = "".join(lines[:20])
    dialect = detect_dialect(sample)
    reader = csv.reader(lines, dialect)
    rows = list(reader)
    col = id_col - 1

    converted = 0
    skipped = 0
    samples: list[tuple[str, str]] = []
    out_rows: list[list[str]] = []

    for row in rows:
        if len(row) <= col:
            out_rows.append(row)
            skipped += 1
            continue
        new_id, changed = decode_dpc_patient_id(row[col])
        if changed:
            converted += 1
            if len(samples) < 5:
                samples.append((row[col], new_id))
            row = list(row)
            row[col] = new_id
        else:
            skipped += 1
        out_rows.append(row)

    if not dry_run:
        dest.parent.mkdir(parents=True, exist_ok=True)
        with dest.open("w", encoding=encoding, newline="") as f:
            writer = csv.writer(f, dialect)
            writer.writerows(out_rows)

    return {
        "src": str(src),
        "dest": str(dest),
        "encoding": encoding,
        "delimiter": dialect.delimiter,
        "rows": len(rows),
        "converted": converted,
        "skipped": skipped,
        "samples": samples,
    }


def default_dest_name(src: Path) -> str:
    stem = src.stem
    if "patient_number_fixed" in stem:
        return src.name
    return f"{stem}_patient_number_fixed{src.suffix}"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--input-dir",
        type=Path,
        default=Path(__file__).resolve().parent / "input",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path(__file__).resolve().parent / "output",
    )
    parser.add_argument("--id-col", type=int, default=2, help="1-based column of データ識別番号")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    if not args.input_dir.exists():
        args.input_dir.mkdir(parents=True, exist_ok=True)
        print(f"created empty input dir: {args.input_dir}", file=sys.stderr)

    files = sorted(
        p
        for p in args.input_dir.iterdir()
        if p.is_file() and p.suffix.lower() in {".txt", ".csv"} and not p.name.startswith(".")
    )
    if not files:
        print(f"no .txt/.csv in {args.input_dir}", file=sys.stderr)
        return 1

    rc = 0
    for src in files:
        dest = args.output_dir / default_dest_name(src)
        try:
            stats = convert_file(src, dest, args.id_col, args.dry_run)
        except Exception as exc:  # noqa: BLE001
            print(f"ERROR {src.name}: {exc}", file=sys.stderr)
            rc = 1
            continue
        mode = "DRY-RUN" if args.dry_run else "WROTE"
        print(f"[{mode}] {src.name}")
        print(f"  encoding={stats['encoding']} delimiter={repr(stats['delimiter'])} rows={stats['rows']}")
        print(f"  converted={stats['converted']} skipped/unchanged={stats['skipped']}")
        if not args.dry_run:
            print(f"  -> {dest.name}")
        for before, after in stats["samples"]:
            print(f"  sample {before} -> {after}")
        if stats["converted"] == 0:
            print("  WARN: 変換0件。列位置や既変換ファイルの可能性あり")
            rc = 1
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
