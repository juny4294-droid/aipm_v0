-- ############################################################################
-- 脳神経外科｜逆紹介候補抽出（鳥取県立中央 / tenant 274）
--
-- 期間     : 2025-08-01 〜 2026-07-31（直近1年）
-- 親集合   : outpatient_ef + dbt_int_doctor_department（担当診療科=脳神経外科）
-- 対象     : N1 ∧ N2 ∧ N3（単純MRIフォロー。1.5T/3.0Tとも候補＝磁場フィルタなし）
-- 除外フラグ: NX1〜NX8
--            ※ NX3 = 神部外来予約のみ（DPC 010010・病名は使わない）
--              → 2026-08-26時点: tenant 274 の外来予約は未投入のため NX3 は適用しない（常に0）
--            ※ NX4 から K178-3（150301110 / 150301210）を除外
--
-- A出力方針
--   - 対象（N1∧N2∧N3）全員を行として出す（≈660人）。除外で行を消さない
--   - 除外条件ごとに 0/1 フラグ列を付ける
--   - `最終候補`=1 が従来の「最終候補」（全除外フラグ=0）
--   - リストAの列名は日本語（条件コード付き。例: NX1_併科）
--
-- 参照
--   - Notion: 20260807_抽出条件確認用_3診療科（病院確認）
--   - 確認スライド v12 / 抽出条件差分
--
-- 注意
--   - 患者ID: CAST(SAFE_CAST(x AS INT64) AS STRING) で正規化（整形と同方針）
--   - NX3: 予約投入後に foro_prd.public_op_optimizer_outpatient_reservations で有効化
-- ############################################################################

-- ---------------------------------------------------------------------------
-- プローブ（任意）: 神部の表記確認
-- ※ op_optimizer_prd は別リージョンの可能性あり。foro_prd（Datastream）を使う
-- ---------------------------------------------------------------------------
/*
SELECT d.name AS doctor_name, COUNT(*) AS n
FROM `medup-foro.foro_prd.public_op_optimizer_outpatient_reservations` AS r
INNER JOIN `medup-foro.foro_prd.public_op_optimizer_doctors` AS d
  ON d.id = r.doctor_id
 AND d.tenant_id = r.tenant_id
WHERE r.tenant_id = 274
  AND d.name LIKE '%神部%'
GROUP BY d.name
ORDER BY n DESC;
*/

-- ============================================================================
-- A. 候補リスト本体
-- ============================================================================
WITH
params AS (
  SELECT
    274 AS tenant_id,
    DATE '2025-08-01' AS period_start,
    DATE '2026-07-31' AS period_end,
    '脳神経外科' AS target_department_name,
    -- NX7: スライド「直近5年以内の入院」（術後6年未満の簡便判定）
    DATE_SUB(DATE '2026-07-31', INTERVAL 5 YEAR) AS sah_lookback_start
),

mri_codes AS (
  SELECT code FROM UNNEST([
    '170020110',  -- MRI 1.5T以上3T未満
    '170033510'   -- MRI 3T以上
  ]) AS code
),

-- NX2: CTのみ（Notion一覧からMRI混在コードを除いたもの）
ct_codes AS (
  SELECT code FROM UNNEST([
    '170011710', '170011810', '170012070', '170027310', '170028610',
    '170033410', '170034910', '170038810', '170038910', '170040210',
    '170040250', '170040410', '170040610', '170704810', '170704910',
    '170901710'
  ]) AS code
),

-- NX4: 血管内（K178-3 除外済み）
vascular_receipt_codes AS (
  SELECT code FROM UNNEST([
    '150254910',  -- K178 1箇所
    '150344410',  -- K178 2箇所以上
    '150355410',  -- K178 脳血管内ステント
    '150273510',  -- K178-2
    '150380850',  -- K178-5
    '150337110',  -- K609-2
    '150453450',  -- K609-2（薬事承認機器）
    '150372510'   -- K178-4
  ]) AS code
),

platelet_codes AS (
  SELECT code FROM UNNEST([
    '160238710',
    '160238610'
  ]) AS code
),

epilepsy_codes AS (
  SELECT code FROM UNNEST([
    '113002850',
    '113029610'
  ]) AS code
),

neuro_doctors AS (
  SELECT
    SAFE_CAST(d.tenant_id AS INT64) AS tenant_id,
    d.doctor_code,
    d.department_name
  FROM `medup-foro.dpc_patient_records_prd.dbt_int_doctor_department` AS d
  CROSS JOIN params AS p
  WHERE SAFE_CAST(d.tenant_id AS INT64) = p.tenant_id
    AND d.department_name = p.target_department_name
),

-- 期間内・全科EF（併科・CT/MRI判定用）。Eレコードのみ
ef_period AS (
  SELECT
    CAST(SAFE_CAST(ef.patient_id AS INT64) AS STRING) AS patient_id,
    ef.doctor_code,
    IFNULL(d.department_name, '未割当') AS department_name,
    ef.outpatient_date.value AS outpatient_date,
    ef.receipt_code
  FROM `medup-foro.dpc_patient_records_prd.outpatient_ef` AS ef
  LEFT JOIN `medup-foro.dpc_patient_records_prd.dbt_int_doctor_department` AS d
    ON ef.doctor_code = d.doctor_code
   AND SAFE_CAST(ef.tenant_id AS INT64) = SAFE_CAST(d.tenant_id AS INT64)
  CROSS JOIN params AS p
  WHERE ef.tenant_id = p.tenant_id
    AND ef.data_type != 'SY'
    AND ef.action_detail_number = 0
    AND ef.outpatient_date.value BETWEEN p.period_start AND p.period_end
),

-- N1∧N2: 期間内に脳神経外科外来あり
neuro_patients AS (
  SELECT DISTINCT
    CAST(SAFE_CAST(ef.patient_id AS INT64) AS STRING) AS patient_id
  FROM `medup-foro.dpc_patient_records_prd.outpatient_ef` AS ef
  INNER JOIN neuro_doctors AS nd
    ON ef.doctor_code = nd.doctor_code
   AND SAFE_CAST(ef.tenant_id AS INT64) = nd.tenant_id
  CROSS JOIN params AS p
  WHERE ef.tenant_id = p.tenant_id
    AND ef.data_type != 'SY'
    AND ef.action_detail_number = 0
    AND ef.outpatient_date.value BETWEEN p.period_start AND p.period_end
),

-- N3: 期間内に単純MRI算定あり（診療科問わず。磁場フィルタなし）
mri_patients AS (
  SELECT DISTINCT e.patient_id
  FROM ef_period AS e
  INNER JOIN mri_codes AS m
    ON e.receipt_code = m.code
),

-- 対象: N1∧N2∧N3
target_patients AS (
  SELECT n.patient_id
  FROM neuro_patients AS n
  INNER JOIN mri_patients AS m
    USING (patient_id)
),

-- NX1: 併科（期間内に脳神経外科以外の担当診療科受診あり）
nx1_multi_dept AS (
  SELECT DISTINCT t.patient_id
  FROM target_patients AS t
  INNER JOIN ef_period AS e
    USING (patient_id)
  CROSS JOIN params AS p
  WHERE e.department_name != p.target_department_name
),

-- NX2: 期間内CTあり
nx2_ct AS (
  SELECT DISTINCT t.patient_id
  FROM target_patients AS t
  INNER JOIN ef_period AS e
    USING (patient_id)
  INNER JOIN ct_codes AS c
    ON e.receipt_code = c.code
),

-- NX3: 神部医師の外来予約（期間内）
-- ※ 2026-08-26: tenant 274 予約未投入のため空集合（除外しない）
nx3_jinbu AS (
  SELECT CAST(NULL AS STRING) AS patient_id
  LIMIT 0
  -- 予約投入後は下記に差し替え:
  -- SELECT DISTINCT CAST(SAFE_CAST(r.patient_number AS INT64) AS STRING) AS patient_id
  -- FROM `medup-foro.foro_prd.public_op_optimizer_outpatient_reservations` AS r
  -- INNER JOIN `medup-foro.foro_prd.public_op_optimizer_doctors` AS d
  --   ON d.id = r.doctor_id AND d.tenant_id = r.tenant_id
  -- CROSS JOIN params AS p
  -- WHERE r.tenant_id = p.tenant_id
  --   AND d.name LIKE '%神部%'
  --   AND DATE(r.reserved_at) BETWEEN p.period_start AND p.period_end
),

-- NX4a: 血管内手術レセ（外来EF・全期間）
nx4_vascular_ef AS (
  SELECT DISTINCT
    CAST(SAFE_CAST(ef.patient_id AS INT64) AS STRING) AS patient_id
  FROM `medup-foro.dpc_patient_records_prd.outpatient_ef` AS ef
  INNER JOIN vascular_receipt_codes AS v
    ON ef.receipt_code = v.code
  CROSS JOIN params AS p
  WHERE ef.tenant_id = p.tenant_id
    AND ef.data_type != 'SY'
    AND ef.action_detail_number = 0
),

-- NX4b: 血管内手術Kコード（入院・全期間）。K178-3 除外
nx4_vascular_adm AS (
  SELECT DISTINCT
    CAST(SAFE_CAST(h.patient_number AS INT64) AS STRING) AS patient_id
  FROM `medup-foro.foro_prd.public_hospital_admissions` AS h
  CROSS JOIN params AS p
  WHERE h.tenant_id = p.tenant_id
    AND h.kcode_operation_1 IS NOT NULL
    AND (
      (STARTS_WITH(h.kcode_operation_1, 'K178') AND NOT STARTS_WITH(h.kcode_operation_1, 'K178-3'))
      OR STARTS_WITH(h.kcode_operation_1, 'K609-2')
    )
),

-- NX4c: 血小板凝集能（外来EF・全期間）
nx4_platelet AS (
  SELECT DISTINCT
    CAST(SAFE_CAST(ef.patient_id AS INT64) AS STRING) AS patient_id
  FROM `medup-foro.dpc_patient_records_prd.outpatient_ef` AS ef
  INNER JOIN platelet_codes AS pl
    ON ef.receipt_code = pl.code
  CROSS JOIN params AS p
  WHERE ef.tenant_id = p.tenant_id
    AND ef.data_type != 'SY'
    AND ef.action_detail_number = 0
),

nx4_vascular_or_platelet AS (
  SELECT patient_id FROM nx4_vascular_ef
  UNION DISTINCT
  SELECT patient_id FROM nx4_vascular_adm
  UNION DISTINCT
  SELECT patient_id FROM nx4_platelet
),

-- NX5: 最新MRIと同日に造影剤使用加算（MRI）
latest_mri AS (
  SELECT
    e.patient_id,
    MAX(e.outpatient_date) AS latest_mri_date
  FROM ef_period AS e
  INNER JOIN mri_codes AS m
    ON e.receipt_code = m.code
  INNER JOIN target_patients AS t
    USING (patient_id)
  GROUP BY e.patient_id
),

nx5_contrast_mri AS (
  -- 造影剤使用加算は明細行（action_detail_number > 0）に載るため、E行(=0)に絞らない
  SELECT DISTINCT lm.patient_id
  FROM latest_mri AS lm
  INNER JOIN `medup-foro.dpc_patient_records_prd.outpatient_ef` AS ef
    ON CAST(SAFE_CAST(ef.patient_id AS INT64) AS STRING) = lm.patient_id
   AND ef.outpatient_date.value = lm.latest_mri_date
  CROSS JOIN params AS p
  WHERE ef.tenant_id = p.tenant_id
    AND ef.data_type != 'SY'
    AND ef.receipt_code = '170020470'
),

-- NX6: 期間内てんかん指導料
nx6_epilepsy AS (
  SELECT DISTINCT t.patient_id
  FROM target_patients AS t
  INNER JOIN ef_period AS e
    USING (patient_id)
  INNER JOIN epilepsy_codes AS ep
    ON e.receipt_code = ep.code
),

-- NX7: くも膜下出血 DPC・直近5年以内退院
nx7_sah AS (
  SELECT DISTINCT
    CAST(SAFE_CAST(h.patient_number AS INT64) AS STRING) AS patient_id
  FROM `medup-foro.foro_prd.public_hospital_admissions` AS h
  CROSS JOIN params AS p
  WHERE h.tenant_id = p.tenant_id
    AND h.dpc_code IS NOT NULL
    AND STARTS_WITH(h.dpc_code, '010020')
    AND h.admission_ended_on > p.sah_lookback_start
    AND h.admission_ended_on <= p.period_end
),

-- NX8: 期間内に脳神経外科から逆紹介済
nx8_reverse_referred AS (
  SELECT DISTINCT
    CAST(SAFE_CAST(r.patient_id AS INT64) AS STRING) AS patient_id
  FROM `medup-foro.foro_prd.public_reverse_referrals` AS r
  INNER JOIN `medup-foro.foro_prd.public_own_departments` AS dept
    ON dept.id = r.specialty_id
  INNER JOIN `medup-foro.foro_prd.public_own_department_tenants` AS odt
    ON odt.own_department_id = dept.id
   AND odt.tenant_id = r.tenant_id
  CROSS JOIN params AS p
  WHERE r.tenant_id = p.tenant_id
    AND dept.name = p.target_department_name
    AND r.reverse_referral_date BETWEEN p.period_start AND p.period_end
)

SELECT
  t.patient_id AS `患者ID`,
  IF(nx1.patient_id IS NOT NULL, 1, 0) AS `NX1_併科`,
  IF(nx2.patient_id IS NOT NULL, 1, 0) AS `NX2_CT`,
  IF(nx3.patient_id IS NOT NULL, 1, 0) AS `NX3_神部`,
  IF(nx4.patient_id IS NOT NULL, 1, 0) AS `NX4_血管内`,
  IF(nx5.patient_id IS NOT NULL, 1, 0) AS `NX5_造影MRI`,
  IF(nx6.patient_id IS NOT NULL, 1, 0) AS `NX6_てんかん`,
  IF(nx7.patient_id IS NOT NULL, 1, 0) AS `NX7_SAH`,
  IF(nx8.patient_id IS NOT NULL, 1, 0) AS `NX8_逆紹介済`,
  IF(
    nx1.patient_id IS NULL
    AND nx2.patient_id IS NULL
    AND nx3.patient_id IS NULL
    AND nx4.patient_id IS NULL
    AND nx5.patient_id IS NULL
    AND nx6.patient_id IS NULL
    AND nx7.patient_id IS NULL
    AND nx8.patient_id IS NULL,
    1,
    0
  ) AS `最終候補`
FROM target_patients AS t
LEFT JOIN nx1_multi_dept AS nx1 USING (patient_id)
LEFT JOIN nx2_ct AS nx2 USING (patient_id)
LEFT JOIN nx3_jinbu AS nx3 USING (patient_id)
LEFT JOIN nx4_vascular_or_platelet AS nx4 USING (patient_id)
LEFT JOIN nx5_contrast_mri AS nx5 USING (patient_id)
LEFT JOIN nx6_epilepsy AS nx6 USING (patient_id)
LEFT JOIN nx7_sah AS nx7 USING (patient_id)
LEFT JOIN nx8_reverse_referred AS nx8 USING (patient_id)
ORDER BY t.patient_id
;


-- ============================================================================
-- B. ファネル件数（Aをコメントアウトして単体実行）
-- ============================================================================
/*
WITH
params AS (
  SELECT
    274 AS tenant_id,
    DATE '2025-08-01' AS period_start,
    DATE '2026-07-31' AS period_end,
    '脳神経外科' AS target_department_name,
    DATE_SUB(DATE '2026-07-31', INTERVAL 5 YEAR) AS sah_lookback_start
),
mri_codes AS (
  SELECT code FROM UNNEST(['170020110', '170033510']) AS code
),
ct_codes AS (
  SELECT code FROM UNNEST([
    '170011710', '170011810', '170012070', '170027310', '170028610',
    '170033410', '170034910', '170038810', '170038910', '170040210',
    '170040250', '170040410', '170040610', '170704810', '170704910',
    '170901710'
  ]) AS code
),
vascular_receipt_codes AS (
  SELECT code FROM UNNEST([
    '150254910', '150344410', '150355410', '150273510',
    '150380850', '150337110', '150453450', '150372510'
  ]) AS code
),
platelet_codes AS (
  SELECT code FROM UNNEST(['160238710', '160238610']) AS code
),
epilepsy_codes AS (
  SELECT code FROM UNNEST(['113002850', '113029610']) AS code
),
neuro_doctors AS (
  SELECT
    SAFE_CAST(d.tenant_id AS INT64) AS tenant_id,
    d.doctor_code,
    d.department_name
  FROM `medup-foro.dpc_patient_records_prd.dbt_int_doctor_department` AS d
  CROSS JOIN params AS p
  WHERE SAFE_CAST(d.tenant_id AS INT64) = p.tenant_id
    AND d.department_name = p.target_department_name
),
ef_period AS (
  SELECT
    CAST(SAFE_CAST(ef.patient_id AS INT64) AS STRING) AS patient_id,
    IFNULL(d.department_name, '未割当') AS department_name,
    ef.outpatient_date.value AS outpatient_date,
    ef.receipt_code
  FROM `medup-foro.dpc_patient_records_prd.outpatient_ef` AS ef
  LEFT JOIN `medup-foro.dpc_patient_records_prd.dbt_int_doctor_department` AS d
    ON ef.doctor_code = d.doctor_code
   AND SAFE_CAST(ef.tenant_id AS INT64) = SAFE_CAST(d.tenant_id AS INT64)
  CROSS JOIN params AS p
  WHERE ef.tenant_id = p.tenant_id
    AND ef.data_type != 'SY'
    AND ef.action_detail_number = 0
    AND ef.outpatient_date.value BETWEEN p.period_start AND p.period_end
),
neuro_patients AS (
  SELECT DISTINCT CAST(SAFE_CAST(ef.patient_id AS INT64) AS STRING) AS patient_id
  FROM `medup-foro.dpc_patient_records_prd.outpatient_ef` AS ef
  INNER JOIN neuro_doctors AS nd
    ON ef.doctor_code = nd.doctor_code
   AND SAFE_CAST(ef.tenant_id AS INT64) = nd.tenant_id
  CROSS JOIN params AS p
  WHERE ef.tenant_id = p.tenant_id
    AND ef.data_type != 'SY'
    AND ef.action_detail_number = 0
    AND ef.outpatient_date.value BETWEEN p.period_start AND p.period_end
),
mri_patients AS (
  SELECT DISTINCT e.patient_id
  FROM ef_period AS e
  INNER JOIN mri_codes AS m ON e.receipt_code = m.code
),
target_patients AS (
  SELECT n.patient_id
  FROM neuro_patients AS n
  INNER JOIN mri_patients AS m USING (patient_id)
),
nx1 AS (
  SELECT DISTINCT t.patient_id
  FROM target_patients AS t
  INNER JOIN ef_period AS e USING (patient_id)
  CROSS JOIN params AS p
  WHERE e.department_name != p.target_department_name
),
nx2 AS (
  SELECT DISTINCT t.patient_id
  FROM target_patients AS t
  INNER JOIN ef_period AS e USING (patient_id)
  INNER JOIN ct_codes AS c ON e.receipt_code = c.code
),
nx3 AS (
  -- 予約未投入のため空（投入後は reservations × doctors の神部クエリに戻す）
  SELECT CAST(NULL AS STRING) AS patient_id
  LIMIT 0
),
nx4 AS (
  SELECT patient_id FROM (
    SELECT DISTINCT CAST(SAFE_CAST(ef.patient_id AS INT64) AS STRING) AS patient_id
    FROM `medup-foro.dpc_patient_records_prd.outpatient_ef` AS ef
    INNER JOIN vascular_receipt_codes AS v ON ef.receipt_code = v.code
    CROSS JOIN params AS p
    WHERE ef.tenant_id = p.tenant_id AND ef.data_type != 'SY' AND ef.action_detail_number = 0
    UNION DISTINCT
    SELECT DISTINCT CAST(SAFE_CAST(h.patient_number AS INT64) AS STRING) AS patient_id
    FROM `medup-foro.foro_prd.public_hospital_admissions` AS h
    CROSS JOIN params AS p
    WHERE h.tenant_id = p.tenant_id
      AND h.kcode_operation_1 IS NOT NULL
      AND (
        (STARTS_WITH(h.kcode_operation_1, 'K178') AND NOT STARTS_WITH(h.kcode_operation_1, 'K178-3'))
        OR STARTS_WITH(h.kcode_operation_1, 'K609-2')
      )
    UNION DISTINCT
    SELECT DISTINCT CAST(SAFE_CAST(ef.patient_id AS INT64) AS STRING) AS patient_id
    FROM `medup-foro.dpc_patient_records_prd.outpatient_ef` AS ef
    INNER JOIN platelet_codes AS pl ON ef.receipt_code = pl.code
    CROSS JOIN params AS p
    WHERE ef.tenant_id = p.tenant_id AND ef.data_type != 'SY' AND ef.action_detail_number = 0
  )
),
latest_mri AS (
  SELECT e.patient_id, MAX(e.outpatient_date) AS latest_mri_date
  FROM ef_period AS e
  INNER JOIN mri_codes AS m ON e.receipt_code = m.code
  INNER JOIN target_patients AS t USING (patient_id)
  GROUP BY e.patient_id
),
nx5 AS (
  -- 造影剤使用加算は明細行（action_detail_number > 0）に載るため、E行(=0)に絞らない
  SELECT DISTINCT lm.patient_id
  FROM latest_mri AS lm
  INNER JOIN `medup-foro.dpc_patient_records_prd.outpatient_ef` AS ef
    ON CAST(SAFE_CAST(ef.patient_id AS INT64) AS STRING) = lm.patient_id
   AND ef.outpatient_date.value = lm.latest_mri_date
  CROSS JOIN params AS p
  WHERE ef.tenant_id = p.tenant_id
    AND ef.data_type != 'SY'
    AND ef.receipt_code = '170020470'
),
nx6 AS (
  SELECT DISTINCT t.patient_id
  FROM target_patients AS t
  INNER JOIN ef_period AS e USING (patient_id)
  INNER JOIN epilepsy_codes AS ep ON e.receipt_code = ep.code
),
nx7 AS (
  SELECT DISTINCT CAST(SAFE_CAST(h.patient_number AS INT64) AS STRING) AS patient_id
  FROM `medup-foro.foro_prd.public_hospital_admissions` AS h
  CROSS JOIN params AS p
  WHERE h.tenant_id = p.tenant_id
    AND h.dpc_code IS NOT NULL
    AND STARTS_WITH(h.dpc_code, '010020')
    AND h.admission_ended_on > p.sah_lookback_start
    AND h.admission_ended_on <= p.period_end
),
nx8 AS (
  SELECT DISTINCT CAST(SAFE_CAST(r.patient_id AS INT64) AS STRING) AS patient_id
  FROM `medup-foro.foro_prd.public_reverse_referrals` AS r
  INNER JOIN `medup-foro.foro_prd.public_own_departments` AS dept
    ON dept.id = r.specialty_id
  INNER JOIN `medup-foro.foro_prd.public_own_department_tenants` AS odt
    ON odt.own_department_id = dept.id AND odt.tenant_id = r.tenant_id
  CROSS JOIN params AS p
  WHERE r.tenant_id = p.tenant_id
    AND dept.name = p.target_department_name
    AND r.reverse_referral_date BETWEEN p.period_start AND p.period_end
),
funnel AS (
  SELECT
    (SELECT COUNT(*) FROM neuro_patients) AS n_n1_n2_neuro,
    (SELECT COUNT(*) FROM target_patients) AS n_n3_target,
    COUNTIF(nx1.patient_id IS NOT NULL) AS n_nx1,
    COUNTIF(nx2.patient_id IS NOT NULL) AS n_nx2,
    COUNTIF(nx3.patient_id IS NOT NULL) AS n_nx3,
    COUNTIF(nx4.patient_id IS NOT NULL) AS n_nx4,
    COUNTIF(nx5.patient_id IS NOT NULL) AS n_nx5,
    COUNTIF(nx6.patient_id IS NOT NULL) AS n_nx6,
    COUNTIF(nx7.patient_id IS NOT NULL) AS n_nx7,
    COUNTIF(nx8.patient_id IS NOT NULL) AS n_nx8,
    COUNTIF(
      nx1.patient_id IS NULL
      AND nx2.patient_id IS NULL
      AND nx3.patient_id IS NULL
      AND nx4.patient_id IS NULL
      AND nx5.patient_id IS NULL
      AND nx6.patient_id IS NULL
      AND nx7.patient_id IS NULL
      AND nx8.patient_id IS NULL
    ) AS n_final_candidates
  FROM target_patients AS t
  LEFT JOIN nx1 USING (patient_id)
  LEFT JOIN nx2 USING (patient_id)
  LEFT JOIN nx3 USING (patient_id)
  LEFT JOIN nx4 USING (patient_id)
  LEFT JOIN nx5 USING (patient_id)
  LEFT JOIN nx6 USING (patient_id)
  LEFT JOIN nx7 USING (patient_id)
  LEFT JOIN nx8 USING (patient_id)
)
SELECT * FROM funnel;
*/
