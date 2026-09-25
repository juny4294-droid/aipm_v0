#!/usr/bin/env python3
"""Product部門方針.pptx を Google スライドにアップロード（Drive API で変換）。"""

from __future__ import annotations

import sys
from pathlib import Path

from google.auth import default
from google.auth.exceptions import DefaultCredentialsError, RefreshError
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError
from googleapiclient.http import MediaFileUpload

DIR = Path(__file__).resolve().parent
PPTX = DIR / "Product部門方針.pptx"
LINK_FILE = DIR / "Product部門方針-google-slides.url"

# 既存の Product部門方針 Drive ファイル（Google スライドなら上書き更新）
EXISTING_FILE_ID = "1LMZ5Sdq7RqS8aegh0Y-TmIUuU6Qe7_LX"

DRIVE_SCOPE = "https://www.googleapis.com/auth/drive"
AUTH_HINT = """
Google ドライブへのアップロードには認証が必要です。ターミナルで次を実行してください:

  gcloud auth application-default login --scopes=https://www.googleapis.com/auth/drive

完了後、もう一度:

  python3 upload-to-google-slides.py

手動で行う場合:
  1. https://drive.google.com を開く
  2. Product部門方針.pptx をドラッグ＆ドロップ
  3. ファイルを右クリック →「アプリで開く」→「Google スライド」
"""


def _edit_link(file_id: str, web_view_link: str | None) -> str:
    if web_view_link and "/presentation/" in web_view_link:
        return web_view_link.replace("/view", "/edit").split("?")[0]
    return f"https://docs.google.com/presentation/d/{file_id}/edit"


def main() -> None:
    if not PPTX.exists():
        print(f"先に build-product-slides.py を実行してください: {PPTX}", file=sys.stderr)
        sys.exit(1)

    try:
        creds, _ = default(scopes=[DRIVE_SCOPE])
    except (DefaultCredentialsError, RefreshError) as e:
        print(f"認証エラー: {e}", file=sys.stderr)
        print(AUTH_HINT, file=sys.stderr)
        sys.exit(1)

    drive = build("drive", "v3", credentials=creds)
    media = MediaFileUpload(
        str(PPTX),
        mimetype="application/vnd.openxmlformats-officedocument.presentationml.presentation",
        resumable=True,
    )

    file_id: str | None = None
    link: str | None = None

    try:
        existing = drive.files().get(
            fileId=EXISTING_FILE_ID,
            fields="id,name,mimeType",
            supportsAllDrives=True,
        ).execute()
        if existing.get("mimeType") == "application/vnd.google-apps.presentation":
            updated = drive.files().update(
                fileId=EXISTING_FILE_ID,
                body={"name": "Product部門方針"},
                media_body=media,
                fields="id,webViewLink",
                supportsAllDrives=True,
            ).execute()
            file_id = updated["id"]
            link = _edit_link(file_id, updated.get("webViewLink"))
            print(f"既存の Google スライドを更新しました:\n  {link}")
        else:
            raise ValueError("existing file is not Google Slides")
    except (HttpError, ValueError):
        try:
            created = drive.files().create(
                body={
                    "name": "Product部門方針",
                    "mimeType": "application/vnd.google-apps.presentation",
                },
                media_body=media,
                fields="id,webViewLink",
                supportsAllDrives=True,
            ).execute()
            file_id = created["id"]
            link = _edit_link(file_id, created.get("webViewLink"))
            print(f"新しい Google スライドを作成しました:\n  {link}")
        except HttpError as e:
            if e.resp.status == 403:
                print("Drive API の権限が不足しています。", file=sys.stderr)
                print(AUTH_HINT, file=sys.stderr)
            else:
                print(f"アップロード失敗: {e}", file=sys.stderr)
            sys.exit(1)

    if file_id and link:
        LINK_FILE.write_text(f"[InternetShortcut]\nURL={link}\n", encoding="utf-8")
        print(f"\nショートカット保存: {LINK_FILE.name}")
        print("Google スライド上でテキスト・表を直接編集できます。")


if __name__ == "__main__":
    main()
