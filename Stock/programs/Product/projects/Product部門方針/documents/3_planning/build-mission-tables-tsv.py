#!/usr/bin/env python3
"""ミッションと担当を TSV 出力。Google スプレッドシートに貼って表としてスライドへコピーする用。"""

from __future__ import annotations

from pathlib import Path

from slide_content import SLIDE2

DIR = Path(__file__).resolve().parent
OUT = DIR / "mission-mapping-tables.tsv"


def _section(title: str, subtitle: str, rows: list[tuple[str, str, str]]) -> list[str]:
    lines = [title, subtitle, "ミッション\t現\t1年後"]
    for m, n, f in rows:
        lines.append(f"{m}\t{n}\t{f}")
    lines.append("")
    return lines


def main() -> None:
    lines: list[str] = []
    for team in SLIDE2["teams"]:
        lines += _section(
            f"【{team['name']}｜{team['tag']}】",
            team["outcome"],
            team["rows"],
        )

    cross = SLIDE2["cross"]
    lines += _section(
        f"【{cross['name']}｜{cross['tag']}】",
        cross["outcome"],
        cross["rows_left"] + cross["rows_right"],
    )

    OUT.write_text("\n".join(lines), encoding="utf-8")
    print(f"Created: {OUT}")
    print("  → Google スプレッドシートに貼り付け → 範囲をコピー → スライドに貼り付けで表になります")


if __name__ == "__main__":
    main()
