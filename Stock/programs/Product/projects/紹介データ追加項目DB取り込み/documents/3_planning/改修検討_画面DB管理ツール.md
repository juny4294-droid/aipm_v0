# 改修検討：画面 / DB / 管理ツール

作成日: 2026-07-22  
根拠: [要件](../2_discovery/要件_紹介データ追加項目DB取り込み.md) / 現行コード調査  
ステータス: **仮説検証中（As-Is整理＋ギャップ洗い出し）**

---

## 0. 結論サマリ

現状は「画面とテナントDBの一部カラムは既にあるが、**管理ツール→テナントDBへの取り込み経路が未接続**」が最大のギャップ。

| 要求項目 | テナントDB (`referrals`) | 紹介履歴画面 | レポート | 管理ツール→テナント反映 |
|---------|-------------------------|-------------|---------|----------------------|
| 初診/再診 | ✅ `first_visit_flag`（1=初診 / 2=再診） | ❌ 列なし（APIフィルタは常に All 固定） | △ APIは対応、集計は未使用 | ❌ INSERT時に **常に1固定** |
| 紹介元医師 | ✅ `doctor_name_from` | ✅ `enabledAdditionalReferralData` 時 | 対象外（要件通り） | ❌ BulkCreateで未マッピング |
| 紹介先医師 | ✅ `doctor_name_to` | ✅ 同上 | 対象外 | ❌ 同上 |
| 紹介目的 / 主訴 | △ `reason_for_presenting`（統合1カラム） | ✅ 「紹介事由・主訴」として表示 | 要検討 | ❌ 同上 |
| 紹介方法（Fax/Web/電話） | ❌ なし | ❌ なし | ❌ なし | ❌ なし |

→ 今回の本丸は **管理ツール側の取り込み拡張＋テナント反映**。画面は既存フラグ活用で足りる部分が多く、追加は主に「紹介方法」「目的/主訴の分離判断」「レポート集計」。

---

## 1. As-Is（現行）

### 1-1. データフロー

```
受領CSV
  → [管理ツール] 紹介マスター作業シート (referral_master_work_sheet_records)
  → クレンジング（医療機関ID / 診療科ID付与）
  → [DataOps DB] referral_masters
  → 作業完了時 BulkCreateReferrals
  → [テナントDB] referrals  （※ここで追加項目が落ちている）
  → foro CRM 紹介履歴 / レポート
```

参考: [管理ツール > dataOps > 機能詳細](https://app.notion.com/p/dffc36620d3f43e3b4c02fe0a7ddf6aa)

### 1-2. DB

#### テナントDB `referrals`（foro）

| カラム | 型 | 備考 |
|--------|----|------|
| `first_visit_flag` | Int default 1 | **1=初診 / 2=再診**。INSERT時はコード上常に1固定 |
| `doctor_name_from` | Text? | 2025-01 追加 |
| `doctor_name_to` | Text? | 2025-01 追加 |
| `reason_for_presenting` | Text? | 2025-01 追加。「紹介事由・主訴」としてUI表示 |

定義: `medup-core-service/packages/foro-prisma/prisma/foro/schema.prisma`（`Referral`）  
マイグレーション: `.../20250128065942_add_doctor_names_reason_to_referrals/`  
フラグ追加: `.../20250202165024_add_enabled_additional_referral_data_to_tenants/`

#### DataOps `referral_masters` / `referral_master_work_sheet_records`

| カラム | 備考 |
|--------|------|
| `received_doctor_name` | 受領側医師名1カラムのみ（from/to未分離） |
| `custom_item` / `custom_item2` / `custom_item3` | 汎用テキスト。用途がコード上は未固定 |

→ 作業シートには「入れ物」はあるが、**テナント `referrals` への伝播ロジックがない**。  
→ DataOps側にも `first_visit_flag` / 紹介方法 / 目的・主訴の専用カラムは **ない**。

#### テナント設定

- `tenants.enabled_additional_referral_data`  
  → 紹介履歴の追加列（医師名・事由・予定入院・手術日・DPC系）の表示ON/OFF  
  → admin-web 上のトグルは見当たらず（DB直設定の可能性・要確認）

### 1-3. 画面（foro CRM）

#### 連携先カルテ・紹介履歴

- パス: `/crms/[id]/referrals`
- 追加列は `enabledAdditionalReferralData === true` のとき表示
  - 紹介先医師 / 紹介元医師 / 紹介事由・主訴
- **初診/再診の列はなし**。APIの `firstVisitFlag` はフロントが常に `All` 固定
- ドキュメント: `apps/foro-crm-web/docs/features/連携先カルテ.md`
- 実装: `ReferralsDetailTable/presenter.tsx`, `ReferralDetailRow`, `CrmsContainer/.../Dashboard/`

#### レポート

| レポート | ページ |
|----------|--------|
| 連携先 | `pages/medical_institutions_reports/[id].tsx` |
| 診療科 | `pages/own_department_reports/[id].tsx` |
| エリア | `pages/area_reports/[id].tsx` |

- 集計キーは件数系のみ（`referral_count` 等）。BQ `ReferralItemMapper` は期間・診療科・施設等で絞り、**初診/再診・方法・目的では絞らない**
- チャートAPIは `first_visit_flag` フィルタ対応ありだが、CRM画面は現状 `all` 固定
- 医師別レポート集計は要件上今回対象外（テキスト表示のみ）

### 1-4. 管理ツール（ギャップの核心）

`ReferralBulkCreateFactory` → `ReferralRepositoryImp` がテナントへ渡す／固定する内容:

- 渡す: medicalInstitutionIdFrom/To, ownDepartmentId, referralDate, patientId, referralControlId, importLogId, tenantId
- **固定**: `firstVisitFlag: 1`（コメント「すでにこのフィールドは使っておらず、すべて1となっている」）
- **渡していない**: `doctorNameFrom/To`, `reasonForPresenting`, custom系

加えて admin ドメインの `Referral` 型自体に追加項目が無い。

主要ファイル:

- `apps/api/src/modules/admin/domains/factories/ReferralBulkCreateFactory.ts`
- `apps/api/src/modules/admin/applications/usecases/BulkCreateReferralsUseCase.ts`
- `apps/api/src/gateways/db/repositories/ReferralRepositoryImp.ts`（INSERT時 firstVisitFlag=1 固定）
- `apps/api/src/modules/dataOps/domains/models/ReferralMaster.ts`
- `apps/api/src/modules/dataOps/domains/factories/ReferralMasterWorkSheetRecordFactory.ts`（CSVパース）
- admin-web: `pages/data-mgmt/tenants/[id]/referral-master-worksheets/`

サンプルCSV列例: `referralDate, departmentName, medicalInstitutionName, ..., doctorName, customItem1..3`  
（ヘッダ `customItem1` とパーサ `customItem` の不一致も要確認）

---

## 2. 項目別 To-Be 案

### A. 初診/再診

| レイヤ | 方針案 |
|--------|--------|
| DB | 既存 `first_visit_flag` を利用（新規カラム不要） |
| 管理ツール | 受領CSVの値を正規化して取り込み。マスタに明示カラム追加（推奨） or custom_item 暫定利用 |
| テナント反映 | BulkCreate で `firstVisitFlag` をセット |
| 画面/レポート | 既存フィルタをそのまま活用。値が入ればレポート分離が効く |
| 構造化 | ○（要件通り）。値域は既存どおり **1=初診 / 2=再診**（不明の扱い要定義） |
| 画面 | 紹介履歴に列追加、または既存フィルタを実データ連動で使えるようにする |

要確認:
- 受領データの表記ゆれ（「初」「初診」「1」等）の正規化ルール
- 欠損時の扱い（現行どおり1固定か、null/不明を許容するか）
- 紹介履歴に初再診列を出すか、レポート軸のみか

### B. 紹介元医師 / 紹介先医師

| レイヤ | 方針案 |
|--------|--------|
| DB | 既存 `doctor_name_from` / `doctor_name_to` |
| 管理ツール | 受領CSVからテキストで保持。`received_doctor_name` の意味（元/先どちらか）を明確化し、不足分はカラム追加 |
| テナント反映 | BulkCreate で両カラムへマッピング |
| 画面 | 既存列＋`enabledAdditionalReferralData` |
| 構造化/レポート | 今回対象外（テキスト表示のみ） |

要確認:
- `received_doctor_name` が現状どの列に対応しているか（DataOps運用実態）
- 紹介元・紹介先の両方が受領CSVに常にあるか

### C. 紹介目的 / 主訴

| レイヤ | 方針案（分岐） |
|--------|----------------|
| **案1（最小）** | 既存 `reason_for_presenting` に結合テキストで入れる。表示ラベルは現状維持 |
| **案2（分離）** | `reason_for_presenting`＝紹介目的、新規 `chief_complaint`＝主訴。画面列も分割 |
| レポート | 要件は「要検討」。まずは履歴表示のみでも可 |

要確認（要件にも明記）:
- 既存ユーザーのデータ実態を見て **分けるか統合か**
- レポート集計までやるか（構造化マスタが必要になる）

### D. 紹介方法（Fax・Web・電話）

| レイヤ | 方針案 |
|--------|--------|
| DB | **新規カラム必要**（例: `referral_method` text or enum）。構造化対象 |
| 管理ツール | 受領値の正規化マスタ（Fax/Web/電話/その他） |
| テナント反映 | BulkCreate でセット |
| 画面 | 紹介履歴に列追加。表示は `enabledAdditionalReferralData` 連動か、別フラグか要相談 |
| レポート | 集計軸追加（連携先／診療科／エリア） |

要確認:
- 「緊急紹介 vs 予定紹介」は紹介方法と同列か別項目か（要件メモに両方のニーズ）
- 値域・未知値の扱い

---

## 3. レイヤ別改修スコープ（案）

### 3-1. DB

| # | 内容 | 優先 | 備考 |
|---|------|------|------|
| D1 | `referrals` への取り込みマッピング修正（既存3+flag） | ★必須 | スキーマ追加なしで価値が出る |
| D2 | `referral_method` 追加 | ★必須 | 紹介方法 |
| D3 | DataOps `referral_masters` / worksheet に明示カラム追加 | ★必須 | custom_item流用は運用負債になりやすい |
| D4 | `chief_complaint` 分離 | 要判断 | データ実態確認後 |
| D5 | レポート用の集計マスタ（方法・初再診） | 中 | 構造化方針確定後 |

洗替方針（黒川さん会話）: **まとめて1回**。カラム追加後は利用希望テナントで全期間再提示・洗替想定。

### 3-2. 管理ツール

| # | 内容 | 優先 |
|---|------|------|
| M1 | CSV取込スキーマ拡張（新列のパース） | ★ |
| M2 | 作業シートUIに新列表示 | ★ |
| M3 | マスター完了→BulkCreate のフィールド伝播 | ★（ボトルネック解消） |
| M4 | 初診/再診・紹介方法の正規化ルール | ★ |
| M5 | DataOps前処理の見直し | 後期（黒川さん調整） |

要件メモ通り **「管理ツールへのインポート処理が早くできると全体が進む」**。

### 3-3. 画面（foro CRM）

| # | 内容 | 対象画面 | 優先 |
|---|------|---------|------|
| U1 | 既存追加列の表示確認（データが入れば見える） | 連携先カルテ → 分析タブ → **紹介履歴**（`/crms/[id]/referrals`） | ★（改修小） |
| U2 | 紹介方法列の追加 | 同上（紹介履歴テーブル） | ★ |
| U3 | 紹介目的/主訴の列分割（案2の場合） | 同上（紹介履歴テーブル） | 要判断 |
| U4 | テナント別 表示/非表示 | 同上（紹介履歴の追加列表示制御） | 要相談（既存フラグ流用可否） |
| U5 | レポート：初再診は既存、紹介方法の軸追加 | **連携先レポート** / **診療科レポート** / **エリアレポート** | 中 |
| U6 | レポート：紹介目的の集計 | 同上（3種レポート） | 要検討 |

---

## 4. 推奨進め方（段階）

要件の段階イメージを、実装ギャップに合わせて具体化:

1. **スキーマ＋マッピング設計確定**（本ドキュメントの要確認を潰す）
2. **管理ツール取込〜BulkCreate伝播**（M1–M4 / D1–D3）← 最先
3. **画面：紹介方法列＋表示フラグ方針**（U2 / U4）
4. **レポート軸**（U5、必要なら U6）
5. **DataOps前処理見直し**（後期・黒川さん）
6. **洗替オペレーション設計**（利用希望テナント向け全期間再提示）

---

## 5. 要確認リスト（次の議論用）

1. 紹介目的と主訴は **分離するか / `reason_for_presenting` 統合のままか**
2. 紹介方法の値域と、「緊急/予定」は同項目か別項目か
3. 初診/再診の欠損・表記ゆれルール（現行1固定をやめるか／不明値の扱い）
4. 紹介履歴のテナント別表示は既存 `enabledAdditionalReferralData` で足りるか（ON方法含む）
5. レポートで今回やる軸は「初再診＋紹介方法」まででよいか（目的は後回し可か／BQ改修要否）
6. DataOps `custom_item*` / `received_doctor_name` の現行運用マッピング（黒川さん確認）
7. `received_doctor_name` → from / to のどちらに載せるか（現状1カラム）
8. 洗替対象テナントの優先順位と、既存 `referral_control_id` 重複制約の扱い
9. CSVヘッダ `customItem1` とパーサ `customItem` の不一致有無

---

## 6. 参考リンク

- 要件: [馬場さん向け要件](https://app.notion.com/p/3561da5a7f3b8108b6dbf26e5a40d223)
- バックログ: [紹介データ追加項目DB取り込み](https://app.notion.com/p/3561da5a7f3b80f4804ce5b52aeaf192)
- DataOps説明: [管理ツール > dataOps > 機能詳細](https://app.notion.com/p/dffc36620d3f43e3b4c02fe0a7ddf6aa)
- 取込条件: [取り込み対象データの条件](https://app.notion.com/p/e2af196c6fab437e80f49e8b55bb9323)
