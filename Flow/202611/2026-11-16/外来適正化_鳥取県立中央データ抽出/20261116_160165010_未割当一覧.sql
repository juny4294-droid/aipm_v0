-- 160165010 のうち、担当診療科マスタに医師が無い行（未割当）
-- 期間: 2025-10-01〜2026-09-30 / tenant 274
-- 1行 = E行の診療行為1回。明細行は同じ行為の内訳なので出さない
-- 医師名は public_op_optimizer_doctors.dpc_doctor_code が鳥取では未設定のため空になる

WITH
params AS (
  SELECT
    274 AS tenant_id,
    DATE '2025-10-01' AS period_start,
    DATE '2026-09-30' AS period_end,
    '脳神経外科' AS neuro_name
),
receipt_dept AS (
  SELECT code, name FROM UNNEST([
    STRUCT('01' AS code, '内科' AS name),
    STRUCT('06', '消化器科'),
    STRUCT('09', '小児科'),
    STRUCT('15', '呼吸器外科'),
    STRUCT('16', '心臓血管外科'),
    STRUCT('26', '眼科'),
    STRUCT('27', '耳鼻咽喉科'),
    STRUCT('30', '放射線科'),
    STRUCT('31', '麻酔科')
  ])
),
base AS (
  SELECT
    CAST(SAFE_CAST(ef.patient_id AS INT64) AS STRING) AS patient_id,
    ef.doctor_code,
    ef.receipt_code,
    ef.action_name,
    ef.outpatient_date.value AS outpatient_date,
    IFNULL(SAFE_CAST(ef.number_of_action AS INT64), 0) AS number_of_action,
    ef.actual_points_amount,
    ef.specialty_code,
    ef.receipt_department_classification,
    DATE_DIFF(ef.outpatient_date.value, ef.patient_birth_date.value, YEAR) AS age_at_visit
  FROM `medup-foro.dpc_patient_records_prd.outpatient_ef` AS ef
  LEFT JOIN `medup-foro.dpc_patient_records_prd.dbt_int_doctor_department` AS d
    ON ef.doctor_code = d.doctor_code
   AND SAFE_CAST(ef.tenant_id AS INT64) = SAFE_CAST(d.tenant_id AS INT64)
  CROSS JOIN params AS p
  WHERE ef.tenant_id = p.tenant_id
    AND ef.data_type != 'SY'
    AND ef.action_detail_number = 0
    AND ef.receipt_code = '160165010'
    AND ef.outpatient_date.value BETWEEN p.period_start AND p.period_end
    AND d.doctor_code IS NULL
),
ef_dept AS (
  SELECT
    CAST(SAFE_CAST(ef.patient_id AS INT64) AS STRING) AS patient_id,
    ef.outpatient_date.value AS outpatient_date,
    ef.receipt_code,
    d.department_name
  FROM `medup-foro.dpc_patient_records_prd.outpatient_ef` AS ef
  INNER JOIN `medup-foro.dpc_patient_records_prd.dbt_int_doctor_department` AS d
    ON ef.doctor_code = d.doctor_code
   AND SAFE_CAST(ef.tenant_id AS INT64) = SAFE_CAST(d.tenant_id AS INT64)
  CROSS JOIN params AS p
  WHERE ef.tenant_id = p.tenant_id
    AND ef.data_type != 'SY'
    AND ef.action_detail_number = 0
    AND ef.outpatient_date.value BETWEEN p.period_start AND p.period_end
),
same_day AS (
  SELECT
    b.patient_id,
    b.outpatient_date,
    b.doctor_code,
    STRING_AGG(DISTINCT e.department_name, '、' ORDER BY e.department_name) AS same_day_departments,
    MAX(IF(e.department_name = '脳神経外科', 1, 0)) AS same_day_neuro,
    MAX(IF(e.receipt_code = '160072370', 1, 0)) AS same_day_pulse_doppler
  FROM base AS b
  LEFT JOIN ef_dept AS e
    ON b.patient_id = e.patient_id
   AND b.outpatient_date = e.outpatient_date
  GROUP BY b.patient_id, b.outpatient_date, b.doctor_code
),
neuro_in_period AS (
  SELECT DISTINCT patient_id
  FROM ef_dept
  CROSS JOIN params AS p
  WHERE department_name = p.neuro_name
),
doctor_size AS (
  SELECT doctor_code, COUNT(DISTINCT patient_id) AS doctor_patient_count
  FROM base
  GROUP BY doctor_code
),
patient_size AS (
  SELECT patient_id, COUNT(*) AS patient_action_count
  FROM base
  GROUP BY patient_id
)
SELECT
  b.patient_id AS `患者ID`,
  b.doctor_code AS `医師コード`,
  IFNULL(doc.name, '') AS `医師名`,
  b.receipt_code AS `レセプトコード`,
  b.action_name AS `レセプト名称`,
  CAST(b.outpatient_date AS STRING) AS `診療日`,
  b.age_at_visit AS `年齢`,
  b.number_of_action AS `回数`,
  b.actual_points_amount AS `点数`,
  b.specialty_code AS `EF診療科コード`,
  IFNULL(sp.name, '') AS `EF診療科名`,
  b.receipt_department_classification AS `レセプト診療科コード`,
  IFNULL(rd.name, '') AS `レセプト診療科名`,
  IFNULL(s.same_day_departments, '') AS `同日の割当済み診療科`,
  IF(s.same_day_neuro = 1, 'あり', 'なし') AS `同日脳神経外科受診`,
  IF(n.patient_id IS NOT NULL, 'あり', 'なし') AS `期間内脳神経外科受診`,
  IF(s.same_day_pulse_doppler = 1, 'あり', 'なし') AS `同日パルスドプラ加算`,
  ds.doctor_patient_count AS `この医師の患者数`,
  ps.patient_action_count AS `この患者の算定回数`
FROM base AS b
LEFT JOIN `medup-foro.foro_prd.public_op_optimizer_doctors` AS doc
  ON doc.tenant_id = 274
 AND doc.dpc_doctor_code = b.doctor_code
LEFT JOIN `medup-foro.foro_prd.public_dpc_specialty_codes` AS sp
  ON sp.code = b.specialty_code
LEFT JOIN receipt_dept AS rd
  ON rd.code = b.receipt_department_classification
LEFT JOIN same_day AS s
  ON s.patient_id = b.patient_id
 AND s.outpatient_date = b.outpatient_date
 AND s.doctor_code = b.doctor_code
LEFT JOIN neuro_in_period AS n
  ON n.patient_id = b.patient_id
LEFT JOIN doctor_size AS ds
  ON ds.doctor_code = b.doctor_code
LEFT JOIN patient_size AS ps
  ON ps.patient_id = b.patient_id
ORDER BY ds.doctor_patient_count DESC, b.doctor_code, b.outpatient_date, b.patient_id
;
