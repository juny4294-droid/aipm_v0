# 鳥取県立中央データ抽出

## 概要
鳥取県立中央病院向け。整形・泌尿器・脳外の逆紹介候補リスト抽出（条件確定→クエリ化→リスト出し）。

## 開始日
2026-08-07（条件整理開始）／Stock化: 2026-08-24

## 終了予定日
TBD（リスト出し・最終確認後）

## 主要ステークホルダー
- Jun.Yamada / shota.kurokawa（Data・クエリ）
- Naoki Yoshida（CS・条件確認とりまとめ）
- かん（byeongseon.kang）
- 病院側: 建部先生・橋本様 ほか各診療科

## 正本リンク
- Slack: [#foro_ps_tottori](https://medup.slack.com/archives/C0A81UB623B)
- Notion作業メモ: [20260805_逆紹介データ抽出クエリ作成](https://app.notion.com/p/3b11da5a7f3b80fe9444f13313f96adf)
- 週次: [20260820_鳥取県立中央病院_週次定例](https://app.notion.com/p/3c11da5a7f3b809e8cfefbd56078b9ff)
- Flow: `Flow/202608/2026-08-07/外来適正化_鳥取県立中央データ抽出/`
- Flow（本日）: `Flow/202608/2026-08-24/外来適正化_鳥取県立中央データ抽出/`

## テナント
tenant 274。親集合は `outpatient_ef` を直近1年で期間絞り（`patient_summary_by_department` は使わない）

## 月次手順
脳神経外科: `documents/4_executing/脳神経外科_月次抽出手順.md`
