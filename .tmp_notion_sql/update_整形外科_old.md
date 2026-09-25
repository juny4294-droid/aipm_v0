<details>
<summary>整形外科</summary>
	```sql
-- ############################################################################
-- 整形外科｜逆紹介候補抽出（鳥取県立中央 / tenant 274）
--
-- 期間     : 2025-08-01 〜 2026-07-31（直近1年。年度ではない）
-- 親集合   : outpatient_ef（受診日で期間絞り）+ 医師マスタの担当診療科
-- 対象     : O1 ∧ O2 ∧ O3
-- 除外     : OX2（非観血的整復）∨ OX3（整形から逆紹介済）
--            ※ OX1（CT/MRI）・ギプス除外は実装しない（v20確定）
--
-- 参照
--   - Notion: 20260807_抽出条件確認用_3診療科
--   - 患者サマリー定義の medical_service_category 優先順位
--   - 黒川さん鳥取SQL（医師→診療科。実装は dbt_int_doctor_department）
--
-- 注意
--   - 患者ID突合: EFはゼロ埋め文字列（例 0001948881）、逆紹介・入院は非ゼロ埋めのことがある。
--     いずれも CAST(SAFE_CAST(x AS INT64) AS STRING) で正規化して突合する。
-- ############################################################################

-- ============================================================================
-- A. 候補リスト本体
-- ============================================================================
WITH
params AS (
  SELECT
    274 AS tenant_id,
    DATE '2025-08-01' AS period_start,
    DATE '2026-07-31' AS period_end,
    '整形外科' AS target_department_name
),

-- 医師→担当診療科（※doctor_code_master は Sheets 外部表で Drive 権限が要るため、
--   実体テーブル dbt_int_doctor_department を使う）
ortho_doctors AS (
  SELECT
    SAFE_CAST(d.tenant_id AS INT64) AS tenant_id,
    d.doctor_code,
    d.department_name
  FROM `medup-foro.dpc_patient_records_prd.dbt_int_doctor_department` AS d
  CROSS JOIN params AS p
  WHERE SAFE_CAST(d.tenant_id AS INT64) = p.tenant_id
    AND d.department_name = p.target_department_name
),

-- 期間内・整形医師担当の外来EF（Eレコードのみ。Fは件数2倍になる）
ortho_ef AS (
  SELECT
    ef.tenant_id,
    CAST(SAFE_CAST(ef.patient_id AS INT64) AS STRING) AS patient_id,
    ef.doctor_code,
    od.department_name,
    ef.outpatient_date.value AS outpatient_date,
    ef.receipt_code,
    ef.action_name
  FROM `medup-foro.dpc_patient_records_prd.outpatient_ef` AS ef
  INNER JOIN ortho_doctors AS od
    ON ef.doctor_code = od.doctor_code
   AND SAFE_CAST(ef.tenant_id AS INT64) = od.tenant_id
  CROSS JOIN params AS p
  WHERE ef.tenant_id = p.tenant_id
    AND ef.data_type != 'SY'
    AND ef.action_detail_number = 0
    AND ef.outpatient_date.value BETWEEN p.period_start AND p.period_end
),

-- 患者×整形：行為フラグ・受診日数（サマリー定義に準拠）
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
  FROM ortho_ef
  GROUP BY patient_id
),

-- 同期間・整形での入院（様式1）。カテゴリ「1.入院」用
admission_ortho AS (
  SELECT DISTINCT
    CAST(SAFE_CAST(h.patient_number AS INT64) AS STRING) AS patient_id
  FROM `medup-foro.foro_prd.public_hospital_admissions` AS h
  LEFT JOIN `medup-foro.foro_prd.public_dpc_specialty_codes` AS c
    ON c.code = h.dpc_specialty_code
  CROSS JOIN params AS p
  WHERE h.tenant_id = p.tenant_id
    AND (c.name = p.target_department_name OR c.name LIKE '%整形%')
    AND (
      h.admission_started_on BETWEEN p.period_start AND p.period_end
      OR h.admission_ended_on BETWEEN p.period_start AND p.period_end
    )
),

-- カテゴリ付与（サマリー定義と同じ優先順位）
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
  LEFT JOIN admission_ortho AS a
    USING (patient_id)
),

-- O1〜O3: 最大行為が 1.入院 / 2.初診 以外（= 処置/手術/注射以下）
target_patients AS (
  SELECT *
  FROM categorized
  WHERE medical_service_category NOT IN ('1.入院', '2.初診')
),

-- OX2: 期間内に非観血的整復（骨折／脱臼）あり（患者単位・整形EF上）
ox2_noninvasive_reduction AS (
  SELECT DISTINCT
    patient_id
  FROM ortho_ef
  WHERE receipt_code IN (
    -- 骨折非観血的整復術（K044系等）
    '150016510', '150016610', '150016710', '150016810', '150016910',
    '150017010', '150017110', '150017210', '150017310', '150060410',
    '150114610', '150115010',
    -- 関節脱臼非観血的整復術（K061系等）
    '150033810', '150033910', '150034010', '150034110', '150034210',
    '150034310', '150034410', '150034510', '150034610', '150034710',
    '150035050', '150035110', '150114810'
  )
),

-- OX3: 期間内に整形外科から逆紹介済み
-- ※ public_own_departments 自体に tenant_id は無く、紐づけは own_department_tenants
ox3_reverse_referred AS (
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
  IF(ox2.patient_id IS NOT NULL, 1, 0) AS ox2_noninvasive_reduction_flag,
  IF(ox3.patient_id IS NOT NULL, 1, 0) AS ox3_reverse_referred_flag
FROM target_patients AS t
LEFT JOIN ox2_noninvasive_reduction AS ox2
  USING (patient_id)
LEFT JOIN ox3_reverse_referred AS ox3
  USING (patient_id)
WHERE ox2.patient_id IS NULL
  AND ox3.patient_id IS NULL
ORDER BY t.patient_id
;


-- ============================================================================
-- B. ファネル件数（上のクエリをコメントアウトして単体実行）
-- ============================================================================
/*
WITH
params AS (
  SELECT
    274 AS tenant_id,
    DATE '2025-08-01' AS period_start,
    DATE '2026-07-31' AS period_end,
    '整形外科' AS target_department_name
),
ortho_doctors AS (
  SELECT
    SAFE_CAST(d.tenant_id AS INT64) AS tenant_id,
    d.doctor_code,
    d.department_name
  FROM `medup-foro.dpc_patient_records_prd.dbt_int_doctor_department` AS d
  CROSS JOIN params AS p
  WHERE SAFE_CAST(d.tenant_id AS INT64) = p.tenant_id
    AND d.department_name = p.target_department_name
),
ortho_ef AS (
  SELECT
    CAST(SAFE_CAST(ef.patient_id AS INT64) AS STRING) AS patient_id,
    ef.outpatient_date.value AS outpatient_date,
    ef.receipt_code
  FROM `medup-foro.dpc_patient_records_prd.outpatient_ef` AS ef
  INNER JOIN ortho_doctors AS od
    ON ef.doctor_code = od.doctor_code
   AND SAFE_CAST(ef.tenant_id AS INT64) = od.tenant_id
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
    MAX(CASE WHEN receipt_code IN ('170033410','170012070','170011810','170035010','170020110','170020470') THEN 1 ELSE 0 END) AS ct_imaging_flag,
    MAX(CASE WHEN STARTS_WITH(receipt_code, '170') THEN 1 ELSE 0 END) AS imaging_flag,
    MAX(CASE WHEN STARTS_WITH(receipt_code, '160') THEN 1 ELSE 0 END) AS exam_flag,
    MAX(CASE WHEN STARTS_WITH(receipt_code, '12') THEN 1 ELSE 0 END) AS medication_flag,
    MAX(CASE WHEN receipt_code IN ('180756010','180024710') THEN 1 ELSE 0 END) AS rehabilitation_flag
  FROM ortho_ef
  GROUP BY patient_id
),
admission_ortho AS (
  SELECT DISTINCT CAST(SAFE_CAST(h.patient_number AS INT64) AS STRING) AS patient_id
  FROM `medup-foro.foro_prd.public_hospital_admissions` AS h
  LEFT JOIN `medup-foro.foro_prd.public_dpc_specialty_codes` AS c
    ON c.code = h.dpc_specialty_code
  CROSS JOIN params AS p
  WHERE h.tenant_id = p.tenant_id
    AND (c.name = p.target_department_name OR c.name LIKE '%整形%')
    AND (
      h.admission_started_on BETWEEN p.period_start AND p.period_end
      OR h.admission_ended_on BETWEEN p.period_start AND p.period_end
    )
),
categorized AS (
  SELECT
    f.patient_id,
    CASE
      WHEN a.patient_id IS NOT NULL THEN '1.入院'
      WHEN f.first_visit_flag = 1 THEN '2.初診'
      WHEN f.follow_up_visit_flag = 1
        AND (f.procedure_flag = 1 OR f.surgery_flag = 1 OR f.injection_flag = 1)
        THEN '3.処置/手術/注射'
      WHEN f.follow_up_visit_flag = 1 AND f.ct_imaging_flag = 1 THEN '4.CT/MRI'
      WHEN f.follow_up_visit_flag = 1 AND (f.imaging_flag = 1 OR f.exam_flag = 1)
        THEN '5.検査（US・XP含む）'
      WHEN f.follow_up_visit_flag = 1 AND f.medication_flag = 1 THEN '6.投薬'
      WHEN f.follow_up_visit_flag = 1 AND f.rehabilitation_flag = 1 THEN '7.リハ'
      WHEN f.follow_up_visit_flag = 1 THEN '8.再診'
      ELSE '9.その他'
    END AS medical_service_category
  FROM patient_flags AS f
  LEFT JOIN admission_ortho AS a USING (patient_id)
),
ox2 AS (
  SELECT DISTINCT patient_id
  FROM ortho_ef
  WHERE receipt_code IN (
    '150016510','150016610','150016710','150016810','150016910',
    '150017010','150017110','150017210','150017310','150060410',
    '150114610','150115010',
    '150033810','150033910','150034010','150034110','150034210',
    '150034310','150034410','150034510','150034610','150034710',
    '150035050','150035110','150114810'
  )
),
ox3 AS (
  SELECT DISTINCT CAST(SAFE_CAST(r.patient_id AS INT64) AS STRING) AS patient_id
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
),
funnel AS (
  SELECT
    (SELECT COUNT(DISTINCT patient_id) FROM ortho_ef) AS n_o1_o2_ortho_visits,
    (SELECT COUNT(*) FROM categorized WHERE medical_service_category NOT IN ('1.入院','2.初診')) AS n_o3_target,
    (SELECT COUNT(*) FROM categorized c WHERE medical_service_category NOT IN ('1.入院','2.初診') AND EXISTS (SELECT 1 FROM ox2 WHERE ox2.patient_id = c.patient_id)) AS n_ox2,
    (SELECT COUNT(*) FROM categorized c WHERE medical_service_category NOT IN ('1.入院','2.初診') AND EXISTS (SELECT 1 FROM ox3 WHERE ox3.patient_id = c.patient_id)) AS n_ox3,
    (
      SELECT COUNT(*)
      FROM categorized c
      WHERE medical_service_category NOT IN ('1.入院','2.初診')
        AND NOT EXISTS (SELECT 1 FROM ox2 WHERE ox2.patient_id = c.patient_id)
        AND NOT EXISTS (SELECT 1 FROM ox3 WHERE ox3.patient_id = c.patient_id)
    ) AS n_final_candidates
)
SELECT * FROM funnel;
*/
	```
</details>