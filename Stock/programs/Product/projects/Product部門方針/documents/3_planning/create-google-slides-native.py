#!/usr/bin/env python3
"""Google スライド API でネイティブ形式のプレゼンを作成（PPTX 変換不要）。"""

from __future__ import annotations

import sys
import uuid
from pathlib import Path

from google.auth import default
from google.auth.exceptions import DefaultCredentialsError, RefreshError
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError

from slide_content import SLIDE1, SLIDE2

DIR = Path(__file__).resolve().parent
LINK_FILE = DIR / "Product部門方針-google-slides.url"

SCOPES = [
    "https://www.googleapis.com/auth/presentations",
    "https://www.googleapis.com/auth/drive.file",
]

AUTH_HINT = """
認証が必要です。ターミナルで次を実行してください:

  gcloud auth application-default login \\
    --scopes=https://www.googleapis.com/auth/presentations,https://www.googleapis.com/auth/drive

完了後:

  python3 create-google-slides-native.py
"""


def _id(prefix: str) -> str:
    return f"{prefix}_{uuid.uuid4().hex[:12]}"


def _emu(inches: float) -> int:
    return int(inches * 914400)


def _hex_rgb(hex_color: str) -> dict:
    h = hex_color.lstrip("#")
    return {
        "red": int(h[0:2], 16) / 255,
        "green": int(h[2:4], 16) / 255,
        "blue": int(h[4:6], 16) / 255,
    }


def _shape(page_id: str, obj_id: str, x: float, y: float, w: float, h: float) -> dict:
    return {
        "createShape": {
            "objectId": obj_id,
            "shapeType": "TEXT_BOX",
            "elementProperties": {
                "pageObjectId": page_id,
                "size": {
                    "width": {"magnitude": _emu(w), "unit": "EMU"},
                    "height": {"magnitude": _emu(h), "unit": "EMU"},
                },
                "transform": {
                    "scaleX": 1,
                    "scaleY": 1,
                    "translateX": _emu(x),
                    "translateY": _emu(y),
                    "unit": "EMU",
                },
            },
        }
    }


def _text(obj_id: str, content: str) -> dict:
    return {"insertText": {"objectId": obj_id, "text": content, "insertionIndex": 0}}


def _style(obj_id: str, size: float = 12, bold: bool = False, color: str | None = None) -> dict:
    fields = ["fontSize", "bold"]
    style: dict = {
        "fontSize": {"magnitude": size, "unit": "PT"},
        "bold": bold,
    }
    if color:
        style["foregroundColor"] = {"opaqueColor": {"rgbColor": _hex_rgb(color)}}
        fields.append("foregroundColor")
    return {
        "updateTextStyle": {
            "objectId": obj_id,
            "style": style,
            "textRange": {"type": "ALL"},
            "fields": ",".join(fields),
        }
    }


def _fill(obj_id: str, color: str) -> dict:
    return {
        "updateShapeProperties": {
            "objectId": obj_id,
            "shapeProperties": {
                "shapeBackgroundFill": {
                    "solidFill": {"color": {"rgbColor": _hex_rgb(color)}}
                }
            },
            "fields": "shapeBackgroundFill",
        }
    }


def _table(page_id: str, obj_id: str, x: float, y: float, w: float, h: float, rows: int, cols: int) -> dict:
    return {
        "createTable": {
            "objectId": obj_id,
            "elementProperties": {
                "pageObjectId": page_id,
                "size": {
                    "width": {"magnitude": _emu(w), "unit": "EMU"},
                    "height": {"magnitude": _emu(h), "unit": "EMU"},
                },
                "transform": {
                    "scaleX": 1,
                    "scaleY": 1,
                    "translateX": _emu(x),
                    "translateY": _emu(y),
                    "unit": "EMU",
                },
            },
            "rows": rows,
            "columns": cols,
        }
    }


def _cell_text(table_id: str, row: int, col: int, text: str) -> dict:
    return {
        "insertText": {
            "objectId": table_id,
            "cellLocation": {"rowIndex": row, "columnIndex": col},
            "text": text,
            "insertionIndex": 0,
        }
    }


def _cell_style(table_id: str, row: int, col: int, size: float = 8, bold: bool = False) -> dict:
    return {
        "updateTextStyle": {
            "objectId": table_id,
            "cellLocation": {"rowIndex": row, "columnIndex": col},
            "style": {"fontSize": {"magnitude": size, "unit": "PT"}, "bold": bold},
            "textRange": {"type": "ALL"},
            "fields": "fontSize,bold",
        }
    }


def _mission_table_requests(page_id: str, prefix: str, x: float, y: float, w: float, h: float, rows_data: list) -> list:
    req: list = []
    table_id = _id(prefix)
    req.append(_table(page_id, table_id, x, y, w, h, 1 + len(rows_data), 3))
    headers = ("ミッション", "現", "1年後")
    for c, htxt in enumerate(headers):
        req.append(_cell_text(table_id, 0, c, htxt))
        req.append(_cell_style(table_id, 0, c, size=8, bold=True))
    for r, (mission, now, future) in enumerate(rows_data, start=1):
        req.append(_cell_text(table_id, r, 0, mission))
        req.append(_cell_style(table_id, r, 0, size=8, bold=True))
        req.append(_cell_text(table_id, r, 1, now))
        req.append(_cell_style(table_id, r, 1, size=8))
        req.append(_cell_text(table_id, r, 2, future))
        req.append(_cell_style(table_id, r, 2, size=8))
    return req


def build_slide1_requests(page_id: str) -> list:
    data = SLIDE1
    req: list = []

    title_id = _id("s1_title")
    req += [_shape(page_id, title_id, 0.35, 0.2, 12.5, 0.45), _text(title_id, data["title"]), _style(title_id, 24, True)]

    vision_id = _id("s1_vision")
    req += [_shape(page_id, vision_id, 0.35, 0.62, 12.5, 0.35), _text(vision_id, data["vision"]), _style(vision_id, 14, True, "#2f6fed")]

    note_id = _id("s1_note")
    req += [_shape(page_id, note_id, 0.35, 0.95, 12.5, 0.3), _text(note_id, data["vision_note"]), _style(note_id, 10, color="#555555")]

    col_w = 4.0
    gap = 0.1
    top = 1.35
    for i, team in enumerate(data["teams"]):
        left = 0.35 + (col_w + gap) * i
        hdr_id = _id(f"s1_hdr{i}")
        req += [_shape(page_id, hdr_id, left, top, col_w, 0.55), _fill(hdr_id, team["color"])]
        hdr_txt = f"{team['name']}　{team['tag']}\n{team['outcome']}"
        req += [_text(hdr_id, hdr_txt), _style(hdr_id, 10, True, "#ffffff")]

        body_id = _id(f"s1_body{i}")
        bullets = "\n".join(f"• {b}" for b in team["bullets"])
        req += [_shape(page_id, body_id, left + 0.08, top + 0.62, col_w - 0.16, 1.9), _text(body_id, bullets), _style(body_id, 9)]

    band_top = 4.05
    for j, band in enumerate((data["cross_top"], data["cross_bottom"])):
        band_id = _id(f"s1_band{j}")
        req += [_shape(page_id, band_id, 0.35, band_top, 12.5, 0.72), _fill(band_id, "#f3f0f8")]
        band_txt = f"{band['label']}\n{band['items']}\n\n{band['members']}"
        req += [_text(band_id, band_txt), _style(band_id, 9, color="#444444")]
        band_top += 0.8

    goal_id = _id("s1_goal")
    req += [_shape(page_id, goal_id, 0.35, 5.65, 12.5, 0.55), _fill(goal_id, "#2f6fed")]
    req += [_text(goal_id, data["goal_2027"]), _style(goal_id, 12, True, "#ffffff")]

    return req


def build_slide2_requests(page_id: str) -> list:
    data = SLIDE2
    req: list = []

    title_id = _id("s2_title")
    req += [_shape(page_id, title_id, 0.3, 0.15, 12.6, 0.4), _text(title_id, data["title"]), _style(title_id, 20, True)]

    sub_id = _id("s2_sub")
    req += [_shape(page_id, sub_id, 0.3, 0.52, 12.6, 0.25), _text(sub_id, data["subtitle"]), _style(sub_id, 8, color="#555555")]

    col_w = 4.0
    gap = 0.08
    top = 0.82
    hdr_h = 0.55
    tbl_h = 2.35

    for i, team in enumerate(data["teams"]):
        left = 0.3 + (col_w + gap) * i
        hdr_id = _id(f"s2_hdr{i}")
        req += [_shape(page_id, hdr_id, left, top, col_w, hdr_h), _fill(hdr_id, team["color"])]
        req += [_text(hdr_id, f"{team['name']}　{team['tag']}\n{team['outcome']}"), _style(hdr_id, 9, True, "#ffffff")]
        req += _mission_table_requests(page_id, f"s2_tbl{i}", left, top + hdr_h, col_w, tbl_h, list(team["rows"]))

    cross = data["cross"]
    cross_top = top + hdr_h + tbl_h + 0.12
    cross_hdr_id = _id("s2_cross_hdr")
    req += [_shape(page_id, cross_hdr_id, 0.3, cross_top, 12.6, 0.5), _fill(cross_hdr_id, cross["color"])]
    req += [_text(cross_hdr_id, f"{cross['name']}　{cross['tag']}\n{cross['outcome']}"), _style(cross_hdr_id, 9, True, "#ffffff")]

    half_w = 6.2
    tbl_top = cross_top + 0.5
    req += _mission_table_requests(page_id, "s2_cross_l", 0.3, tbl_top, half_w, 1.55, list(cross["rows_left"]))
    req += _mission_table_requests(page_id, "s2_cross_r", 0.3 + half_w + 0.06, tbl_top, half_w, 1.55, list(cross["rows_right"]))

    return req


def main() -> None:
    try:
        creds, _ = default(scopes=SCOPES)
    except (DefaultCredentialsError, RefreshError) as e:
        print(f"認証エラー: {e}", file=sys.stderr)
        print(AUTH_HINT, file=sys.stderr)
        sys.exit(1)

    slides = build("slides", "v1", credentials=creds)
    drive = build("drive", "v3", credentials=creds)

    try:
        pres = slides.presentations().create(body={"title": "Product部門方針"}).execute()
        pres_id = pres["presentationId"]
        default_slide = pres["slides"][0]["objectId"]

        slide1_id = _id("slide1")
        slide2_id = _id("slide2")

        requests = [
            {"createSlide": {"objectId": slide1_id, "insertionIndex": 0, "slideLayoutReference": {"predefinedLayout": "BLANK"}}},
            {"createSlide": {"objectId": slide2_id, "insertionIndex": 1, "slideLayoutReference": {"predefinedLayout": "BLANK"}}},
            {"deleteObject": {"objectId": default_slide}},
        ]
        requests += build_slide1_requests(slide1_id)
        requests += build_slide2_requests(slide2_id)

        slides.presentations().batchUpdate(presentationId=pres_id, body={"requests": requests}).execute()

        link = f"https://docs.google.com/presentation/d/{pres_id}/edit"
        LINK_FILE.write_text(f"[InternetShortcut]\nURL={link}\n", encoding="utf-8")

        print("Google スライドを作成しました（ネイティブ形式）:")
        print(f"  {link}")
        print(f"\nショートカット: {LINK_FILE.name}")
        print("\n※ ドライブに上げた .pptx を直接開くとエラーになります。必ずこの URL から開いてください。")

    except HttpError as e:
        if e.resp.status == 403:
            print("API の権限が不足しています。", file=sys.stderr)
            print(AUTH_HINT, file=sys.stderr)
        else:
            print(f"作成失敗: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
