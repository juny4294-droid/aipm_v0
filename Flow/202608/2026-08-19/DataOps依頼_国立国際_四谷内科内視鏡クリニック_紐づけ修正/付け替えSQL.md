# 既存データ付け替えSQL（スクショ①）

> **案件**: 国立国際／四谷内科・内視鏡クリニック 紐づけ修正  
> **変更**: `23197`（四谷・村川内科クリニック）→ `229401`（四谷内科・内視鏡クリニック）  
> **テナント**: `tenant_id = 23`（管理ツールURL実績より。実行前に要再確認）  
> **注意**: 受領名で絞らないと、本当に村川内科宛ての紹介も巻き込む

---

## 0. 前提

| DB | テーブル | 更新カラム |
|----|----------|------------|
| data_ops | `referral_masters` | `medical_institution_id_from` |
| foro（テナント） | `medup_mt_23.referrals` | `medical_institution_id_from` |

医療機関マッピング（`medical_institution_mappings`）は依頼者側で `229401` 済み想定。

---

## 1. data_ops — 確認

```sql
-- 件数・サンプル確認（期待: 管理画面と同じ ~73件前後）
SELECT
  COUNT(*) AS cnt
FROM referral_masters
WHERE tenant_id = 23
  AND medical_institution_id_from = 23197
  AND received_medical_institution_name = '四谷内科・内視鏡クリニック';

SELECT
  id,
  referral_control_id,
  patient_id,
  referral_date,
  received_medical_institution_name,
  received_medical_institution_address,
  medical_institution_id_from,
  medical_institution_id_to,
  work_sheet_id
FROM referral_masters
WHERE tenant_id = 23
  AND medical_institution_id_from = 23197
  AND received_medical_institution_name = '四谷内科・内視鏡クリニック'
ORDER BY referral_date, id
LIMIT 20;

-- 表記ゆれがないか（名前のバリエーション確認）
SELECT
  received_medical_institution_name,
  medical_institution_id_from,
  COUNT(*) AS cnt
FROM referral_masters
WHERE tenant_id = 23
  AND (
    received_medical_institution_name LIKE '%四谷内科%内視鏡%'
    OR medical_institution_id_from IN (23197, 229401)
  )
GROUP BY 1, 2
ORDER BY cnt DESC;
```

---

## 2. data_ops — `referral_masters` 更新

確認済み WHERE（73件）と同じ条件で更新する。

```sql
BEGIN;

UPDATE public.referral_masters AS rm
SET
  medical_institution_id_from = 229401,
  updated_at = NOW()
WHERE rm.tenant_id = 23
  AND rm.medical_institution_id_from = 23197
  AND rm.received_medical_institution_name = '四谷内科・内視鏡クリニック';

SELECT COUNT(*) AS remaining_wrong
FROM public.referral_masters AS rm
WHERE rm.tenant_id = 23
  AND rm.medical_institution_id_from = 23197
  AND rm.received_medical_institution_name = '四谷内科・内視鏡クリニック';
-- 期待: 0

SELECT COUNT(*) AS fixed_count
FROM public.referral_masters AS rm
WHERE rm.tenant_id = 23
  AND rm.medical_institution_id_from = 229401
  AND rm.received_medical_institution_name = '四谷内科・内視鏡クリニック';
-- 期待: 73

COMMIT;
-- おかしければ ROLLBACK;
```

`updated_at` が無い／エラーならその行だけ外す。

**注意**: masters を先に直すと、§3-1 の ID 出力 WHERE が `23197` では 0 件になる。referrals 用の control_id は **masters 更新前に控える**か、更新後は `medical_institution_id_from = 229401` で出し直す。

---

## 3. data_ops — referrals更新用 ID 出力（確認済み: 73件）

AlloyDB `data_ops` で以下が **73件** であることを確認済み（2026-08-20）。

```sql
SELECT rm.*
FROM public.referral_masters AS rm
WHERE rm.tenant_id = 23
  AND rm.medical_institution_id_from = 23197
  AND rm.received_medical_institution_name = '四谷内科・内視鏡クリニック';
```

### 3-1. `referral_control_id` を出す（foro.referrals の IN 用）

```sql
SELECT rm.referral_control_id
FROM public.referral_masters AS rm
WHERE rm.tenant_id = 23
  AND rm.medical_institution_id_from = 23197
  AND rm.received_medical_institution_name = '四谷内科・内視鏡クリニック'
ORDER BY rm.referral_control_id;
```

貼り付けやすい形（カンマ区切り・クォート付き）:

```sql
SELECT string_agg(quote_literal(rm.referral_control_id::text), ', ' ORDER BY rm.referral_control_id)
FROM public.referral_masters AS rm
WHERE rm.tenant_id = 23
  AND rm.medical_institution_id_from = 23197
  AND rm.received_medical_institution_name = '四谷内科・内視鏡クリニック';
```

---

## 4. foro — `referrals` 更新

**接続先**: AlloyDB `foro_prd`（data_ops とは別DB）。  
`referral_control_id` は上の 3-1 の結果を `IN (...)` に貼る。

### 4-1. 更新前確認（出力した ID を `IN` に貼る）

件数:

```sql
SELECT COUNT(*) AS cnt
FROM public.referrals AS r
WHERE r.tenant_id = 23
  AND r.medical_institution_id_from = 23197
  AND r.referral_control_id IN (
    -- 3-1 の結果を貼る
  );
-- 期待: 73
```

明細（サンプル）:

```sql
SELECT
  r.id,
  r.referral_control_id,
  r.patient_id,
  r.referral_date,
  r.medical_institution_id_from,
  r.medical_institution_id_to,
  r.updated_at
FROM public.referrals AS r
WHERE r.tenant_id = 23
  AND r.medical_institution_id_from = 23197
  AND r.referral_control_id IN (
    -- 3-1 の結果を貼る
  )
ORDER BY r.referral_date DESC, r.id
LIMIT 20;
```

IDごとの件数（重複・取りこぼしチェック）:

```sql
SELECT
  r.referral_control_id,
  COUNT(*) AS cnt,
  MIN(r.medical_institution_id_from) AS from_id
FROM public.referrals AS r
WHERE r.tenant_id = 23
  AND r.referral_control_id IN (
    -- 3-1 の結果を貼る
  )
GROUP BY r.referral_control_id
ORDER BY cnt DESC, r.referral_control_id;
-- 期待: 行数 ≈ 73、from_id はすべて 23197
```

`cnt` が 73 で、明細の `medical_institution_id_from` がすべて `23197` なら更新へ進む。

### 4-2. 更新

```sql
BEGIN;

UPDATE public.referrals AS r
SET
  medical_institution_id_from = 229401,
  updated_at = NOW()
WHERE r.tenant_id = 23
  AND r.medical_institution_id_from = 23197
  AND r.referral_control_id IN (
    -- 3-1 の結果を貼る
  );

SELECT
  COUNT(*) AS remaining_wrong
FROM public.referrals AS r
WHERE r.tenant_id = 23
  AND r.medical_institution_id_from = 23197
  AND r.referral_control_id IN (
    -- 同じ IN リスト
  );
-- 期待: 0

SELECT
  COUNT(*) AS fixed_count
FROM public.referrals AS r
WHERE r.tenant_id = 23
  AND r.medical_institution_id_from = 229401
  AND r.referral_control_id IN (
    -- 同じ IN リスト
  );
-- 期待: 73

COMMIT;
-- おかしければ ROLLBACK;
```

`updated_at` が無い／型エラーならその行だけ外す。  
`referral_control_id` が integer の場合は `IN` にクォートなしの数値を貼る。

### 簡易版（非推奨・巻き込み注意）

```sql
-- 危険: tenant=23 の 23197 を全部 229401 にする（村川内科の実紹介を巻き込む）
-- BEGIN;
-- UPDATE public.referrals
-- SET medical_institution_id_from = 229401
-- WHERE tenant_id = 23
--   AND medical_institution_id_from = 23197;
-- COMMIT;
```

---

## 5. マッピング再確認（任意）

```sql
SELECT
  id,
  tenant_id,
  received_medical_institution_name,
  received_medical_institution_address,
  medical_institution_id
FROM medical_institution_mappings
WHERE tenant_id = 23
  AND (
    received_medical_institution_name LIKE '%四谷内科%内視鏡%'
    OR medical_institution_id IN (23197, 229401)
  );
```

期待: 受領名「四谷内科・内視鏡クリニック」→ `229401`。

---

## 6. 実行後チェック

1. 管理ツール 紹介タブで受領名「四谷内科・内視鏡クリニック」→ MIS が `229401`
2. 誤紐づけ `23197` が 0 件
3. foro 紹介履歴でも紹介元が四谷内科・内視鏡クリニックになっている

---

## 変更履歴

| 日付 | 内容 |
|------|------|
| 2026-08-19 | 初版。data_ops `referral_masters` / foro `medup_mt_23.referrals` の付け替えSQL |
| 2026-08-20 | AlloyDBで masters 73件確認。control_id出力・`public.referrals` 更新SQLに更新 |
