<details>
<summary>泌尿器科</summary>
```sql
-- ############################################################################
-- 泌尿器科｜逆紹介候補抽出（鳥取県立中央 / tenant 274）
--
-- 期間     : 2025-08-01 〜 2026-07-31（直近1年。年度ではない）
-- 親集合   : outpatient_ef（受診日で期間絞り）+ dbt_int_doctor_department
-- 対象     : U1 ∧ U2 ∧ (U3 ∨ U4 ∨ U5)
--            U3: 最大行為=4.CT/MRI かつ 泌尿受診 ≤2回
--            U4: 最大行為=5.検査 かつ 泌尿受診 ≤5回
--            U5: 最大行為 IN (6.投薬, 8.再診)
-- 除外     : UX1 併科 / UX2 期間内MRI / UX3 鳥取大学→泌尿紹介
--            UX4 前立腺がん術後5年未満 / UX6 泌尿から逆紹介済
--            ※ UX5（積極的監視疑い）は 8/25合意により 除外もしない・フラグも付けない
--
-- 参照
--   - Notion: 20260807_抽出条件確認用_3診療科
--   - 確認スライド v13 / 抽出条件差分
--
-- 注意
--   - 患者ID: CAST(SAFE_CAST(x AS INT64) AS STRING)
--   - 入院手術Kは kcode_operation_1 のみ（_2以降はスキーマに無い）
-- ############################################################################

-- ---------------------------------------------------------------------------
-- プローブ（任意）
-- ---------------------------------------------------------------------------
/*
-- 泌尿の医師マスタ表記
SELECT department_name, COUNT(*) AS n
FROM `medup-foro.dpc_patient_records_prd.dbt_int_doctor_department`
WHERE SAFE_CAST(tenant_id AS INT64) = 274
  AND department_name LIKE '%泌尿%'
GROUP BY department_name;

-- 鳥取大学の紹介元（名称マスタは tenant_29_view 経由で確認。ID確定済: 75462）
SELECT
  mi.medical_institution_id,
  mi.name,
  COUNT(*) AS n
FROM `medup-foro.foro_prd.public_referrals` AS r
INNER JOIN `medup-foro.foro_prd.tenant_29_view_medical_institutions` AS mi
  ON mi.medical_institution_id = r.medical_institution_id_from
WHERE r.tenant_id = 274
  AND mi.name LIKE '%鳥取大学%'
GROUP BY mi.medical_institution_id, mi.name
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
    '泌尿器科' AS target_department_name,
    -- UX3: 鳥取大学医学部附属病院（tenant_29_view で名称確認済）
    75462 AS tottori_univ_medical_institution_id,
    -- UX4: 退院日から5年未満（期間末日基準）
    DATE_SUB(DATE '2026-07-31', INTERVAL 5 YEAR) AS prostate_surgery_lookback_start
),

mri_codes AS (
  SELECT code FROM UNNEST([
    '170020110',  -- MRI 1.5T以上3T未満
    '170033510'   -- MRI 3T以上
  ]) AS code
),

uro_doctors AS (
  SELECT
    SAFE_CAST(d.tenant_id AS INT64) AS tenant_id,
    d.doctor_code,
    d.department_name
  FROM `medup-foro.dpc_patient_records_prd.dbt_int_doctor_department` AS d
  CROSS JOIN params AS p
  WHERE SAFE_CAST(d.tenant_id AS INT64) = p.tenant_id
    AND d.department_name = p.target_department_name
),

-- 期間内・泌尿医師担当の外来EF（Eレコード）
uro_ef AS (
  SELECT
    ef.tenant_id,
    CAST(SAFE_CAST(ef.patient_id AS INT64) AS STRING) AS patient_id,
    ef.doctor_code,
    ud.department_name,
    ef.outpatient_date.value AS outpatient_date,
    ef.receipt_code,
    ef.action_name
  FROM `medup-foro.dpc_patient_records_prd.outpatient_ef` AS ef
  INNER JOIN uro_doctors AS ud
    ON ef.doctor_code = ud.doctor_code
   AND SAFE_CAST(ef.tenant_id AS INT64) = ud.tenant_id
  CROSS JOIN params AS p
  WHERE ef.tenant_id = p.tenant_id
    AND ef.data_type != 'SY'
    AND ef.action_detail_number = 0
    AND ef.outpatient_date.value BETWEEN p.period_start AND p.period_end
),

-- 期間内・全科EF（併科・MRI判定用）
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

-- 患者×泌尿：行為フラグ・受診日数（サマリー定義に準拠）
patient_flags AS (
  SELECT
    patient_id,
    COUNT(DISTINCT outpatient_date) AS visit_count_in_specialty,
    MAX(CASE WHEN STARTS_WITH(receipt_code, '111') THEN 1 ELSE 0 END) AS first_visit_flag,
    MAX(CASE WHEN STARTS_WITH(receipt_code, '112') THEN 1 ELSE 0 END) AS follow_up_visit_flag,
    MAX(CASE WHEN STARTS_WITH(receipt_code, '140') THEN 1 ELSE 0 END) AS procedure_flag,
    MAX(CASE WHEN STARTS_WITH(receipt_code, '150') THEN 1 ELSE 0 END) AS surgery_flag,
    MAX(CASE WHEN STARTS_WITH(receipt_code, '13') THEN 1 ELSE 0 END) AS injection_flag,
    MAX(
      CASE
        WHEN receipt_code IN (
          '170033410', '170012070', '170011810',
          '170035010', '170020110', '170020470'
        ) THEN 1
        ELSE 0
      END
    ) AS ct_imaging_flag,
    MAX(CASE WHEN STARTS_WITH(receipt_code, '170') THEN 1 ELSE 0 END) AS imaging_flag,
    MAX(CASE WHEN STARTS_WITH(receipt_code, '160') THEN 1 ELSE 0 END) AS exam_flag,
    MAX(CASE WHEN STARTS_WITH(receipt_code, '12') THEN 1 ELSE 0 END) AS medication_flag,
    MAX(
      CASE
        WHEN receipt_code IN ('180756010', '180024710') THEN 1
        ELSE 0
      END
    ) AS rehabilitation_flag
  FROM uro_ef
  GROUP BY patient_id
),

-- 同期間・泌尿での入院（様式1）。カテゴリ「1.入院」用
admission_uro AS (
  SELECT DISTINCT
    CAST(SAFE_CAST(h.patient_number AS INT64) AS STRING) AS patient_id
  FROM `medup-foro.foro_prd.public_hospital_admissions` AS h
  LEFT JOIN `medup-foro.foro_prd.public_dpc_specialty_codes` AS c
    ON c.code = h.dpc_specialty_code
  CROSS JOIN params AS p
  WHERE h.tenant_id = p.tenant_id
    AND (c.name = p.target_department_name OR c.name LIKE '%泌尿%')
    AND (
      h.admission_started_on BETWEEN p.period_start AND p.period_end
      OR h.admission_ended_on BETWEEN p.period_start AND p.period_end
    )
),

categorized AS (
  SELECT
    f.patient_id,
    f.visit_count_in_specialty,
    CASE
      WHEN a.patient_id IS NOT NULL THEN '1.入院'
      WHEN f.first_visit_flag = 1 THEN '2.初診'
      WHEN f.follow_up_visit_flag = 1
        AND (f.procedure_flag = 1 OR f.surgery_flag = 1 OR f.injection_flag = 1)
        THEN '3.処置/手術/注射'
      WHEN f.follow_up_visit_flag = 1 AND f.ct_imaging_flag = 1 THEN '4.CT/MRI'
      WHEN f.follow_up_visit_flag = 1
        AND (f.imaging_flag = 1 OR f.exam_flag = 1)
        THEN '5.検査（US・XP含む）'
      WHEN f.follow_up_visit_flag = 1 AND f.medication_flag = 1 THEN '6.投薬'
      WHEN f.follow_up_visit_flag = 1 AND f.rehabilitation_flag = 1 THEN '7.リハ'
      WHEN f.follow_up_visit_flag = 1 THEN '8.再診'
      ELSE '9.その他'
    END AS medical_service_category
  FROM patient_flags AS f
  LEFT JOIN admission_uro AS a
    USING (patient_id)
),

-- U1∧U2∧(U3∨U4∨U5)
target_patients AS (
  SELECT *
  FROM categorized
  WHERE
    (
      medical_service_category = '4.CT/MRI'
      AND visit_count_in_specialty <= 2
    )
    OR (
      medical_service_category = '5.検査（US・XP含む）'
      AND visit_count_in_specialty <= 5
    )
    OR medical_service_category IN ('6.投薬', '8.再診')
),

-- UX1: 期間内に泌尿以外の外来あり
ux1_multi_dept AS (
  SELECT DISTINCT t.patient_id
  FROM target_patients AS t
  INNER JOIN ef_period AS e
    USING (patient_id)
  CROSS JOIN params AS p
  WHERE e.department_name != p.target_department_name
),

-- UX2: 期間内にMRI算定あり（診療科問わず）
ux2_mri AS (
  SELECT DISTINCT t.patient_id
  FROM target_patients AS t
  INNER JOIN ef_period AS e
    USING (patient_id)
  INNER JOIN mri_codes AS m
    ON e.receipt_code = m.code
),

-- UX3: 鳥取大学 → 泌尿への紹介（紹介日は問わない）
-- ※ foro_prd に medical_institutions 本体が無いため、確認済IDを直指定
ux3_tottori_univ AS (
  SELECT DISTINCT
    CAST(SAFE_CAST(r.patient_id AS INT64) AS STRING) AS patient_id
  FROM `medup-foro.foro_prd.public_referrals` AS r
  INNER JOIN `medup-foro.foro_prd.public_own_departments` AS dept
    ON dept.id = r.specialty_id
  INNER JOIN `medup-foro.foro_prd.public_own_department_tenants` AS odt
    ON odt.own_department_id = dept.id
   AND odt.tenant_id = r.tenant_id
  CROSS JOIN params AS p
  WHERE r.tenant_id = p.tenant_id
    AND dept.name = p.target_department_name
    AND r.medical_institution_id_from = p.tottori_univ_medical_institution_id
),

-- UX4: 前立腺がんDPC + K843系手術 + 退院が直近5年以内
ux4_prostate_surgery AS (
  SELECT DISTINCT
    CAST(SAFE_CAST(h.patient_number AS INT64) AS STRING) AS patient_id
  FROM `medup-foro.foro_prd.public_hospital_admissions` AS h
  CROSS JOIN params AS p
  WHERE h.tenant_id = p.tenant_id
    AND h.dpc_code IS NOT NULL
    AND STARTS_WITH(h.dpc_code, '110080')
    AND h.kcode_operation_1 IS NOT NULL
    AND STARTS_WITH(h.kcode_operation_1, 'K843')
    AND h.admission_ended_on > p.prostate_surgery_lookback_start
    AND h.admission_ended_on <= p.period_end
),

-- UX6: 期間内に泌尿から逆紹介済
ux6_reverse_referred AS (
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
  t.patient_id,
  t.medical_service_category,
  t.visit_count_in_specialty,
  IF(ux1.patient_id IS NOT NULL, 1, 0) AS ux1_multi_dept_flag,
  IF(ux2.patient_id IS NOT NULL, 1, 0) AS ux2_mri_flag,
  IF(ux3.patient_id IS NOT NULL, 1, 0) AS ux3_tottori_univ_flag,
  IF(ux4.patient_id IS NOT NULL, 1, 0) AS ux4_prostate_surgery_flag,
  IF(ux6.patient_id IS NOT NULL, 1, 0) AS ux6_reverse_referred_flag
FROM target_patients AS t
LEFT JOIN ux1_multi_dept AS ux1 USING (patient_id)
LEFT JOIN ux2_mri AS ux2 USING (patient_id)
LEFT JOIN ux3_tottori_univ AS ux3 USING (patient_id)
LEFT JOIN ux4_prostate_surgery AS ux4 USING (patient_id)
LEFT JOIN ux6_reverse_referred AS ux6 USING (patient_id)
WHERE ux1.patient_id IS NULL
  AND ux2.patient_id IS NULL
  AND ux3.patient_id IS NULL
  AND ux4.patient_id IS NULL
  AND ux6.patient_id IS NULL
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
    '泌尿器科' AS target_department_name,
    75462 AS tottori_univ_medical_institution_id,
    DATE_SUB(DATE '2026-07-31', INTERVAL 5 YEAR) AS prostate_surgery_lookback_start
),
mri_codes AS (
  SELECT code FROM UNNEST(['170020110', '170033510']) AS code
),
uro_doctors AS (
  SELECT
    SAFE_CAST(d.tenant_id AS INT64) AS tenant_id,
    d.doctor_code,
    d.department_name
  FROM `medup-foro.dpc_patient_records_prd.dbt_int_doctor_department` AS d
  CROSS JOIN params AS p
  WHERE SAFE_CAST(d.tenant_id AS INT64) = p.tenant_id
    AND d.department_name = p.target_department_name
),
uro_ef AS (
  SELECT
    CAST(SAFE_CAST(ef.patient_id AS INT64) AS STRING) AS patient_id,
    ef.outpatient_date.value AS outpatient_date,
    ef.receipt_code
  FROM `medup-foro.dpc_patient_records_prd.outpatient_ef` AS ef
  INNER JOIN uro_doctors AS ud
    ON ef.doctor_code = ud.doctor_code
   AND SAFE_CAST(ef.tenant_id AS INT64) = ud.tenant_id
  CROSS JOIN params AS p
  WHERE ef.tenant_id = p.tenant_id
    AND ef.data_type != 'SY'
    AND ef.action_detail_number = 0
    AND ef.outpatient_date.value BETWEEN p.period_start AND p.period_end
),
ef_period AS (
  SELECT
    CAST(SAFE_CAST(ef.patient_id AS INT64) AS STRING) AS patient_id,
    IFNULL(d.department_name, '未割当') AS department_name,
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
patient_flags AS (
  SELECT
    patient_id,
    COUNT(DISTINCT outpatient_date) AS visit_count_in_specialty,
    MAX(CASE WHEN STARTS_WITH(receipt_code, '111') THEN 1 ELSE 0 END) AS first_visit_flag,
    MAX(CASE WHEN STARTS_WITH(receipt_code, '112') THEN 1 ELSE 0 END) AS follow_up_visit_flag,
    MAX(CASE WHEN STARTS_WITH(receipt_code, '140') THEN 1 ELSE 0 END) AS procedure_flag,
    MAX(CASE WHEN STARTS_WITH(receipt_code, '150') THEN 1 ELSE 0 END) AS surgery_flag,
    MAX(CASE WHEN STARTS_WITH(receipt_code, '13') THEN 1 ELSE 0 END) AS injection_flag,
    MAX(
      CASE
        WHEN receipt_code IN (
          '170033410', '170012070', '170011810',
          '170035010', '170020110', '170020470'
        ) THEN 1 ELSE 0
      END
    ) AS ct_imaging_flag,
    MAX(CASE WHEN STARTS_WITH(receipt_code, '170') THEN 1 ELSE 0 END) AS imaging_flag,
    MAX(CASE WHEN STARTS_WITH(receipt_code, '160') THEN 1 ELSE 0 END) AS exam_flag,
    MAX(CASE WHEN STARTS_WITH(receipt_code, '12') THEN 1 ELSE 0 END) AS medication_flag,
    MAX(CASE WHEN receipt_code IN ('180756010', '180024710') THEN 1 ELSE 0 END) AS rehabilitation_flag
  FROM uro_ef
  GROUP BY patient_id
),
admission_uro AS (
  SELECT DISTINCT CAST(SAFE_CAST(h.patient_number AS INT64) AS STRING) AS patient_id
  FROM `medup-foro.foro_prd.public_hospital_admissions` AS h
  LEFT JOIN `medup-foro.foro_prd.public_dpc_specialty_codes` AS c
    ON c.code = h.dpc_specialty_code
  CROSS JOIN params AS p
  WHERE h.tenant_id = p.tenant_id
    AND (c.name = p.target_department_name OR c.name LIKE '%泌尿%')
    AND (
      h.admission_started_on BETWEEN p.period_start AND p.period_end
      OR h.admission_ended_on BETWEEN p.period_start AND p.period_end
    )
),
categorized AS (
  SELECT
    f.patient_id,
    f.visit_count_in_specialty,
    CASE
      WHEN a.patient_id IS NOT NULL THEN '1.入院'
      WHEN f.first_visit_flag = 1 THEN '2.初診'
      WHEN f.follow_up_visit_flag = 1
        AND (f.procedure_flag = 1 OR f.surgery_flag = 1 OR f.injection_flag = 1)
        THEN '3.処置/手術/注射'
      WHEN f.follow_up_visit_flag = 1 AND f.ct_imaging_flag = 1 THEN '4.CT/MRI'
      WHEN f.follow_up_visit_flag = 1
        AND (f.imaging_flag = 1 OR f.exam_flag = 1)
        THEN '5.検査（US・XP含む）'
      WHEN f.follow_up_visit_flag = 1 AND f.medication_flag = 1 THEN '6.投薬'
      WHEN f.follow_up_visit_flag = 1 AND f.rehabilitation_flag = 1 THEN '7.リハ'
      WHEN f.follow_up_visit_flag = 1 THEN '8.再診'
      ELSE '9.その他'
    END AS medical_service_category
  FROM patient_flags AS f
  LEFT JOIN admission_uro AS a USING (patient_id)
),
uro_patients AS (
  SELECT DISTINCT patient_id FROM uro_ef
),
target_patients AS (
  SELECT *
  FROM categorized
  WHERE
    (medical_service_category = '4.CT/MRI' AND visit_count_in_specialty <= 2)
    OR (medical_service_category = '5.検査（US・XP含む）' AND visit_count_in_specialty <= 5)
    OR medical_service_category IN ('6.投薬', '8.再診')
),
ux1 AS (
  SELECT DISTINCT t.patient_id
  FROM target_patients AS t
  INNER JOIN ef_period AS e USING (patient_id)
  CROSS JOIN params AS p
  WHERE e.department_name != p.target_department_name
),
ux2 AS (
  SELECT DISTINCT t.patient_id
  FROM target_patients AS t
  INNER JOIN ef_period AS e USING (patient_id)
  INNER JOIN mri_codes AS m ON e.receipt_code = m.code
),
ux3 AS (
  SELECT DISTINCT CAST(SAFE_CAST(r.patient_id AS INT64) AS STRING) AS patient_id
  FROM `medup-foro.foro_prd.public_referrals` AS r
  INNER JOIN `medup-foro.foro_prd.public_own_departments` AS dept
    ON dept.id = r.specialty_id
  INNER JOIN `medup-foro.foro_prd.public_own_department_tenants` AS odt
    ON odt.own_department_id = dept.id AND odt.tenant_id = r.tenant_id
  CROSS JOIN params AS p
  WHERE r.tenant_id = p.tenant_id
    AND dept.name = p.target_department_name
    AND r.medical_institution_id_from = p.tottori_univ_medical_institution_id
),
ux4 AS (
  SELECT DISTINCT CAST(SAFE_CAST(h.patient_number AS INT64) AS STRING) AS patient_id
  FROM `medup-foro.foro_prd.public_hospital_admissions` AS h
  CROSS JOIN params AS p
  WHERE h.tenant_id = p.tenant_id
    AND h.dpc_code IS NOT NULL
    AND STARTS_WITH(h.dpc_code, '110080')
    AND h.kcode_operation_1 IS NOT NULL
    AND STARTS_WITH(h.kcode_operation_1, 'K843')
    AND h.admission_ended_on > p.prostate_surgery_lookback_start
    AND h.admission_ended_on <= p.period_end
),
ux6 AS (
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
    (SELECT COUNT(*) FROM uro_patients) AS n_u1_u2_uro,
    (SELECT COUNT(*) FROM target_patients) AS n_u3_u5_target,
    COUNTIF(ux1.patient_id IS NOT NULL) AS n_ux1,
    COUNTIF(ux2.patient_id IS NOT NULL) AS n_ux2,
    COUNTIF(ux3.patient_id IS NOT NULL) AS n_ux3,
    COUNTIF(ux4.patient_id IS NOT NULL) AS n_ux4,
    COUNTIF(ux6.patient_id IS NOT NULL) AS n_ux6,
    COUNTIF(
      ux1.patient_id IS NULL
      AND ux2.patient_id IS NULL
      AND ux3.patient_id IS NULL
      AND ux4.patient_id IS NULL
      AND ux6.patient_id IS NULL
    ) AS n_final_candidates
  FROM target_patients AS t
  LEFT JOIN ux1 USING (patient_id)
  LEFT JOIN ux2 USING (patient_id)
  LEFT JOIN ux3 USING (patient_id)
  LEFT JOIN ux4 USING (patient_id)
  LEFT JOIN ux6 USING (patient_id)
)
SELECT * FROM funnel;
*/
```
</details>