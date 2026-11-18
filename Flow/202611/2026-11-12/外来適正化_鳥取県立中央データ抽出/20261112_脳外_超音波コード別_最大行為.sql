-- 脳神経外科｜超音波コード別の最大行為（鳥取県立中央 / tenant 274）
-- 実行日: 2026-11-12
-- 期間: 2025-10-01 〜 2026-09-30（11/05 の N4 件数と同じ）
-- 対象コード: 黒川さんが出した超音波関連の請求コード一式（D206 / D215 / D413）
-- コードの有無は脳外受診の E行・明細行の両方。最大行為は 11/05 と同じ（脳外の E行と脳外入院）
-- 同一患者が複数コードを持つ場合、それぞれの列に数え上げる

WITH
params AS (
  SELECT
    274 AS tenant_id,
    DATE '2025-10-01' AS period_start,
    DATE '2026-09-30' AS period_end,
    '脳神経外科' AS target_department_name
),
us_codes AS (
  SELECT code FROM UNNEST([
    '160164970', '160198470',
    '160072110', '160072210', '160165010', '160213010', '160218310',
    '160072450', '160072510', '160072610', '160072750', '160160410',
    '160186610', '160198810', '160213170', '160072910', '160147110',
    '160147210', '160150050', '160161710', '160182970', '160231810'
  ]) AS code
),
categories AS (
  SELECT cat FROM UNNEST([
    '1.入院',
    '2.初診',
    '3.処置/手術/注射',
    '4.CT/MRI',
    '5.検査（US・XP含む）',
    '6.投薬',
    '7.リハ',
    '8.再診',
    '9.その他',
    'E行なし'
  ]) AS cat
),
neuro_doctors AS (
  SELECT
    SAFE_CAST(d.tenant_id AS INT64) AS tenant_id,
    d.doctor_code
  FROM `medup-foro.dpc_patient_records_prd.dbt_int_doctor_department` AS d
  CROSS JOIN params AS p
  WHERE SAFE_CAST(d.tenant_id AS INT64) = p.tenant_id
    AND d.department_name = p.target_department_name
),
neuro_ef AS (
  SELECT
    CAST(SAFE_CAST(ef.patient_id AS INT64) AS STRING) AS patient_id,
    ef.outpatient_date.value AS outpatient_date,
    ef.receipt_code,
    ef.action_detail_number
  FROM `medup-foro.dpc_patient_records_prd.outpatient_ef` AS ef
  INNER JOIN neuro_doctors AS nd
    ON ef.doctor_code = nd.doctor_code
   AND SAFE_CAST(ef.tenant_id AS INT64) = nd.tenant_id
  CROSS JOIN params AS p
  WHERE ef.tenant_id = p.tenant_id
    AND ef.data_type != 'SY'
    AND ef.outpatient_date.value BETWEEN p.period_start AND p.period_end
),
patient_flags AS (
  SELECT
    patient_id,
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
  FROM neuro_ef
  WHERE action_detail_number = 0
  GROUP BY patient_id
),
admission_neuro AS (
  SELECT DISTINCT
    CAST(SAFE_CAST(h.patient_number AS INT64) AS STRING) AS patient_id
  FROM `medup-foro.foro_prd.public_hospital_admissions` AS h
  LEFT JOIN `medup-foro.foro_prd.public_dpc_specialty_codes` AS c
    ON c.code = h.dpc_specialty_code
  CROSS JOIN params AS p
  WHERE h.tenant_id = p.tenant_id
    AND c.name = p.target_department_name
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
      WHEN f.follow_up_visit_flag = 1
        AND (f.imaging_flag = 1 OR f.exam_flag = 1)
        THEN '5.検査（US・XP含む）'
      WHEN f.follow_up_visit_flag = 1 AND f.medication_flag = 1 THEN '6.投薬'
      WHEN f.follow_up_visit_flag = 1 AND f.rehabilitation_flag = 1 THEN '7.リハ'
      WHEN f.follow_up_visit_flag = 1 THEN '8.再診'
      ELSE '9.その他'
    END AS medical_service_category
  FROM patient_flags AS f
  LEFT JOIN admission_neuro AS a
    USING (patient_id)
),
patient_codes AS (
  SELECT DISTINCT
    e.patient_id,
    e.receipt_code AS code
  FROM neuro_ef AS e
  INNER JOIN us_codes AS u
    ON e.receipt_code = u.code
),
tagged AS (
  SELECT
    pc.patient_id,
    pc.code,
    IFNULL(c.medical_service_category, 'E行なし') AS cat
  FROM patient_codes AS pc
  LEFT JOIN categorized AS c
    USING (patient_id)
),
by_cat AS (
  SELECT
    cat.cat AS medical_service_category,
    COUNT(DISTINCT IF(t.code = '160164970', t.patient_id, NULL)) AS c_160164970,
    COUNT(DISTINCT IF(t.code = '160198470', t.patient_id, NULL)) AS c_160198470,
    COUNT(DISTINCT IF(t.code = '160072110', t.patient_id, NULL)) AS c_160072110,
    COUNT(DISTINCT IF(t.code = '160072210', t.patient_id, NULL)) AS c_160072210,
    COUNT(DISTINCT IF(t.code = '160165010', t.patient_id, NULL)) AS c_160165010,
    COUNT(DISTINCT IF(t.code = '160213010', t.patient_id, NULL)) AS c_160213010,
    COUNT(DISTINCT IF(t.code = '160218310', t.patient_id, NULL)) AS c_160218310,
    COUNT(DISTINCT IF(t.code = '160072450', t.patient_id, NULL)) AS c_160072450,
    COUNT(DISTINCT IF(t.code = '160072510', t.patient_id, NULL)) AS c_160072510,
    COUNT(DISTINCT IF(t.code = '160072610', t.patient_id, NULL)) AS c_160072610,
    COUNT(DISTINCT IF(t.code = '160072750', t.patient_id, NULL)) AS c_160072750,
    COUNT(DISTINCT IF(t.code = '160160410', t.patient_id, NULL)) AS c_160160410,
    COUNT(DISTINCT IF(t.code = '160186610', t.patient_id, NULL)) AS c_160186610,
    COUNT(DISTINCT IF(t.code = '160198810', t.patient_id, NULL)) AS c_160198810,
    COUNT(DISTINCT IF(t.code = '160213170', t.patient_id, NULL)) AS c_160213170,
    COUNT(DISTINCT IF(t.code = '160072910', t.patient_id, NULL)) AS c_160072910,
    COUNT(DISTINCT IF(t.code = '160147110', t.patient_id, NULL)) AS c_160147110,
    COUNT(DISTINCT IF(t.code = '160147210', t.patient_id, NULL)) AS c_160147210,
    COUNT(DISTINCT IF(t.code = '160150050', t.patient_id, NULL)) AS c_160150050,
    COUNT(DISTINCT IF(t.code = '160161710', t.patient_id, NULL)) AS c_160161710,
    COUNT(DISTINCT IF(t.code = '160182970', t.patient_id, NULL)) AS c_160182970,
    COUNT(DISTINCT IF(t.code = '160231810', t.patient_id, NULL)) AS c_160231810
  FROM categories AS cat
  LEFT JOIN tagged AS t
    ON t.cat = cat.cat
  GROUP BY cat.cat
),
totals AS (
  SELECT
    '合計' AS medical_service_category,
    COUNT(DISTINCT IF(code = '160164970', patient_id, NULL)) AS c_160164970,
    COUNT(DISTINCT IF(code = '160198470', patient_id, NULL)) AS c_160198470,
    COUNT(DISTINCT IF(code = '160072110', patient_id, NULL)) AS c_160072110,
    COUNT(DISTINCT IF(code = '160072210', patient_id, NULL)) AS c_160072210,
    COUNT(DISTINCT IF(code = '160165010', patient_id, NULL)) AS c_160165010,
    COUNT(DISTINCT IF(code = '160213010', patient_id, NULL)) AS c_160213010,
    COUNT(DISTINCT IF(code = '160218310', patient_id, NULL)) AS c_160218310,
    COUNT(DISTINCT IF(code = '160072450', patient_id, NULL)) AS c_160072450,
    COUNT(DISTINCT IF(code = '160072510', patient_id, NULL)) AS c_160072510,
    COUNT(DISTINCT IF(code = '160072610', patient_id, NULL)) AS c_160072610,
    COUNT(DISTINCT IF(code = '160072750', patient_id, NULL)) AS c_160072750,
    COUNT(DISTINCT IF(code = '160160410', patient_id, NULL)) AS c_160160410,
    COUNT(DISTINCT IF(code = '160186610', patient_id, NULL)) AS c_160186610,
    COUNT(DISTINCT IF(code = '160198810', patient_id, NULL)) AS c_160198810,
    COUNT(DISTINCT IF(code = '160213170', patient_id, NULL)) AS c_160213170,
    COUNT(DISTINCT IF(code = '160072910', patient_id, NULL)) AS c_160072910,
    COUNT(DISTINCT IF(code = '160147110', patient_id, NULL)) AS c_160147110,
    COUNT(DISTINCT IF(code = '160147210', patient_id, NULL)) AS c_160147210,
    COUNT(DISTINCT IF(code = '160150050', patient_id, NULL)) AS c_160150050,
    COUNT(DISTINCT IF(code = '160161710', patient_id, NULL)) AS c_160161710,
    COUNT(DISTINCT IF(code = '160182970', patient_id, NULL)) AS c_160182970,
    COUNT(DISTINCT IF(code = '160231810', patient_id, NULL)) AS c_160231810
  FROM patient_codes
)
SELECT * FROM by_cat
UNION ALL
SELECT * FROM totals
ORDER BY
  CASE medical_service_category WHEN '合計' THEN 1 ELSE 0 END,
  medical_service_category
;
