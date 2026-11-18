#!/usr/bin/env python3
"""公式のセキュリティ告知を読み、watches.yaml のバージョンに当たったものだけ表示する。

このスクリプトは Slack に投稿しない。表示は確認用。
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

import feedparser
import requests
import yaml
from packaging.specifiers import InvalidSpecifier, SpecifierSet
from packaging.version import InvalidVersion, Version

HERE = Path(__file__).resolve().parent
STATE_PATH = HERE / "state.json"
USER_AGENT = "security-advisory-notifier"
MAX_RSS_PAGE_FETCHES = 20
TIMEOUT = 30


def strip_html(text: str) -> str:
    text = re.sub(r"(?i)<br\s*/?>", "\n", text)
    text = re.sub(r"<[^>]+>", " ", text)
    return re.sub(r"[ \t]+", " ", text).strip()


def series_regex(series: str, product: str) -> re.Pattern[str]:
    if product == "PostgreSQL" and series.isdigit():
        return re.compile(rf"(?:\bPostgreSQL\s+{series}\b|\b{series}\.\d+\b)")
    if series.isdigit():
        return re.compile(rf"\b{re.escape(series)}\.\d+\b")
    return re.compile(rf"\b{re.escape(series)}(?:\.\d+)*\b")


def is_security_text(text: str) -> bool:
    return re.search(r"(?i)\b(security|cve-\d{4}-\d+)\b", text) is not None


def version_in_specifier(version: str, raw_range: str) -> bool:
    spec_text = raw_range.replace(",", " ")
    try:
        return Version(version) in SpecifierSet(spec_text)
    except (InvalidSpecifier, InvalidVersion):
        return False


def version_in_nginx_span(version: str, start: str, end: str) -> bool:
    try:
        current = Version(version)
        return Version(start) <= current <= Version(end)
    except InvalidVersion:
        return False


def nginx_affects(text: str, version: str) -> bool:
    # 「Not vulnerable」の中の vulnerable には当てない。
    match = re.search(r"(?i)(?<!not )vulnerable:\s*([^\n]+)", text)
    if not match:
        return False
    blob = match.group(1)
    if re.search(r"(?i)\ball\b", blob):
        return True
    for part in re.split(r"[,]", blob):
        part = part.strip().strip(".")
        span = re.fullmatch(r"(\d+(?:\.\d+)*)-(\d+(?:\.\d+)*)", part)
        if span and version_in_nginx_span(version, span.group(1), span.group(2)):
            return True
    return False


def fetch_text(url: str) -> str:
    response = requests.get(
        url,
        headers={"User-Agent": USER_AGENT},
        timeout=TIMEOUT,
    )
    response.raise_for_status()
    return strip_html(response.text)


def matched_lines(watch: dict, text: str) -> list[dict]:
    product = watch["product"]
    found = []
    for line in watch["lines"]:
        series = line.get("series")
        if series and series_regex(series, product).search(text):
            found.append(line)
        elif not series and nginx_affects(text, line["version"]):
            found.append(line)
    return found


def format_message(product: str, title: str, lines: list[dict], url: str) -> str:
    groups = []
    for line in lines:
        repos = ", ".join(line["repos"])
        note = "。修正版は出ない" if line.get("eol") else ""
        groups.append(f"{repos}（{line['version']}）{note}")
    return f"{product}  {title}\n該当: {'; '.join(groups)}\n{url}"


def rss_items(watch: dict) -> list[dict]:
    parsed = feedparser.parse(
        watch["feed"]["url"],
        agent=USER_AGENT,
        request_headers={"User-Agent": USER_AGENT},
    )
    if parsed.bozo and not parsed.entries:
        raise RuntimeError(parsed.bozo_exception)
    items = []
    fetches = 0
    for entry in parsed.entries:
        title = strip_html(entry.get("title", ""))
        link = entry.get("link", "")
        body = strip_html(entry.get("summary", "") or entry.get("description", ""))
        text = f"{title}\n{body}"
        if watch["product"] == "PostgreSQL" and not title.startswith("PostgreSQL"):
            continue
        # セキュリティかどうかは配信文だけで決める。ページ全体にはメニューの Security が含まれる。
        if watch.get("security_only") and not is_security_text(text):
            continue
        lines = matched_lines(watch, text)
        if not lines and not body and link and fetches < MAX_RSS_PAGE_FETCHES:
            fetches += 1
            text = f"{title}\n{fetch_text(link)}"
            lines = matched_lines(watch, text)
        if lines:
            items.append(
                {
                    "id": entry.get("id") or link,
                    "text": format_message(
                        watch["product"], title or "(無題)", lines, link
                    ),
                }
            )
    return items


def github_items(watch: dict) -> list[dict]:
    repo = watch["feed"]["repo"]
    package = watch["feed"]["package"].lower()
    response = requests.get(
        f"https://api.github.com/repos/{repo}/security-advisories",
        headers={
            "User-Agent": USER_AGENT,
            "Accept": "application/vnd.github+json",
        },
        params={"per_page": 30, "state": "published"},
        timeout=TIMEOUT,
    )
    response.raise_for_status()
    items = []
    for advisory in response.json():
        affected = []
        seen = set()
        for vuln in advisory.get("vulnerabilities") or []:
            name = ((vuln.get("package") or {}).get("name") or "").lower()
            if name != package:
                continue
            raw_range = vuln.get("vulnerable_version_range") or ""
            for line in watch["lines"]:
                key = (line["version"], tuple(line["repos"]))
                if key in seen:
                    continue
                if version_in_specifier(line["version"], raw_range):
                    seen.add(key)
                    affected.append(line)
        if not affected:
            continue
        items.append(
            {
                "id": advisory.get("ghsa_id") or advisory.get("html_url") or "",
                "text": format_message(
                    watch["product"],
                    advisory.get("summary") or advisory.get("ghsa_id") or "(無題)",
                    affected,
                    advisory.get("html_url") or "",
                ),
            }
        )
    return items


def nginx_items(watch: dict) -> list[dict]:
    html = requests.get(
        watch["feed"]["url"],
        headers={"User-Agent": USER_AGENT},
        timeout=TIMEOUT,
    ).text
    items = []
    for raw in re.findall(r"<li><p>(.*?)</p></li>", html, re.S):
        text = strip_html(raw)
        cve = re.search(r"CVE-\d{4}-\d+", text)
        title = text.split("\n", 1)[0]
        link_match = re.search(r'href="([^"]+)"', raw)
        link = link_match.group(1) if link_match else watch["feed"]["url"]
        if cve:
            title = f"{title} ({cve.group(0)})"
        lines = [
            line
            for line in watch["lines"]
            if nginx_affects(text, line["version"])
        ]
        if lines:
            items.append(
                {
                    "id": cve.group(0) if cve else title,
                    "text": format_message(watch["product"], title, lines, link),
                }
            )
    return items


def collect(watch: dict) -> list[str]:
    kind = watch["feed"]["type"]
    if kind == "rss":
        return rss_items(watch)
    if kind == "github_advisories":
        return github_items(watch)
    if kind == "html_headings":
        return nginx_items(watch)
    raise RuntimeError(f"未知の取得方法です: {kind}")


def load_seen() -> set[str]:
    if not STATE_PATH.exists():
        return set()
    return set(json.loads(STATE_PATH.read_text()).get("ids", []))


def save_seen(ids: set[str]) -> None:
    STATE_PATH.write_text(
        json.dumps({"ids": sorted(ids)}, ensure_ascii=False, indent=2) + "\n"
    )


def gather() -> list[dict]:
    watches = yaml.safe_load((HERE / "watches.yaml").read_text())["watches"]
    found = []
    for watch in watches:
        try:
            found.extend(collect(watch))
        except Exception as error:  # noqa: BLE001  取得先ごとの失敗で全体は止めない
            print(f"{watch['product']} の取得失敗: {error}", file=sys.stderr)
    return found


def load_env() -> dict[str, str]:
    env = {}
    for line in (HERE / ".env").read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        env[key.strip()] = value.strip()
    return env


def post_slack(token: str, channel: str, text: str) -> None:
    response = requests.post(
        "https://slack.com/api/chat.postMessage",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json; charset=utf-8",
        },
        json={"channel": channel, "text": text},
        timeout=TIMEOUT,
    )
    response.raise_for_status()
    body = response.json()
    if not body.get("ok"):
        raise RuntimeError(body.get("error") or "Slack への投稿に失敗しました")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--seed",
        action="store_true",
        help="今見えている告知を既読にして、Slack には出さない",
    )
    parser.add_argument(
        "--post",
        action="store_true",
        help="既読でない告知だけを Slack に出す",
    )
    args = parser.parse_args()
    found = gather()
    if args.seed:
        save_seen({item["id"] for item in found if item["id"]})
        print(f"既読にしました: {len(load_seen())} 件")
        print("Slack には出していません。")
        return 0

    if not args.post:
        print("確認表示です。Slack には出しません。")
        print(f"合計 {len(found)} 件（過去分を含む。まだ投稿しない）")
        return 0

    seen = load_seen()
    fresh = [item for item in found if item["id"] and item["id"] not in seen]
    if not fresh:
        print("新しい告知はありません。")
        print("Slack には出していません。")
        return 0

    env = load_env()
    token = env["SLACK_BOT_TOKEN"]
    channel = env["SLACK_CHANNEL"]
    posted = 0
    for item in fresh:
        post_slack(token, channel, item["text"])
        seen.add(item["id"])
        save_seen(seen)
        posted += 1
        print(item["text"].splitlines()[0])
    print(f"投稿しました: {posted} 件")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
