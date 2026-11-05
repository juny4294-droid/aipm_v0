# foro 全体構成

foro の構成図を、ここに足していく。日付の付いた HTML が編集用で、同じ名前の PNG が配る用。

## 図

| 日付 | 図 | 中身 |
|---|---|---|
| 2026-10-14 | [20261014_全体構成.png](20261014_全体構成.png) | 病院に渡しているプロダクトの並び |
| 2026-10-14 | [20261014_インフラ.png](20261014_インフラ.png) | 本番の実行環境とデータの通り道 |

PNG を出し直すときは、このフォルダで `node render.mjs 20261014_インフラ` のように、HTML の拡張子を除いた名前を渡す。省略すると `20261014_全体構成` を撮る。`#sheet` だけを画像にする。

## まだ載せていないこと

- プロダクト同士のデータのつながり。全体構成の図には線を引いていない。
- 画面の中。入退院の画面は [foro入退院モック](../foro入退院モック/screens.md) にある。
- インフラ図で未確認と書いた接続。入退院の画面がどの Cloud Run に乗るか、command / core / crm-api が primary と read のどちらにつながるか。
- 2023-09-14 の [foroCRM 全体像](https://app.notion.com/p/bd7fa7718ac64b03bcfa5ff17cd00fd2) にある Redis、Cloud SQL、SendGrid、Azure AD B2C。今の資料と突き合わせていない。

## 出典

- [20260929-30_開発組織ToBeディスカッション](https://app.notion.com/p/3e91da5a7f3b80a989fed1224d093de0) のプロダクト一覧
- [04.foro CRM](https://app.notion.com/p/0e464442ff284798913a991395c5b487)（外来適正化は CRM のオプション）
- 入退院の画面説明: [screens.md](../foro入退院モック/screens.md)
- 連携マップの使い方の一例: [逆紹介候補先のまとめ印刷](../projects/連携マップデザイン作成/documents/2_discovery/要件_逆紹介候補先まとめ印刷.md)
- インフラ: [AlloyDBの同時接続数変更](https://app.notion.com/p/3ea1da5a7f3b8011b025ff795c025df7)（2026-10-14 の作業計画）、[AlloyDB アラート調査まとめ](https://app.notion.com/p/35a1da5a7f3b80ba8252df4695373236)（2026-05-08）
- 構成管理の共通記載: [foro CRM 構成管理](https://app.notion.com/p/4b6f572bca5549c9880dbefa130a2665)
