-- 担当診療科マスタの脳神経外科の人数と、160165010 の91人の担当医師
-- 期間: 2025-10-01 〜 2026-09-30 / tenant 274
-- 91人は E行の 160165010 が脳神経外科の医師に付いている患者

WITH
params AS (
  SELECT
    274 AS tenant_id,
    DATE '2025-10-01' AS period_start,
    DATE '2026-09-30' AS period_end,
    '脳神経外科' AS target_department_name
),
neuro_doctors AS (
  SELECT DISTINCT
    d.doctor_code
  FROM `medup-foro.dpc_patient_records_prd.dbt_int_doctor_department` AS d
  CROSS JOIN params AS p
  WHERE SAFE_CAST(d.tenant_id AS INT64) = p.tenant_id
    AND d.department_name = p.target_department_name
),
echo_e AS (
  SELECT
    CAST(SAFE_CAST(ef.patient_id AS INT64) AS STRING) AS patient_id,
    ef.doctor_code,
    ef.outpatient_date.value AS outpatient_date
  FROM `medup-foro.dpc_patient_records_prd.outpatient_ef` AS ef
  CROSS JOIN params AS p
  WHERE ef.tenant_id = p.tenant_id
    AND ef.data_type != 'SY'
    AND ef.action_detail_number = 0
    AND ef.receipt_code = '160165010'
    AND ef.outpatient_date.value BETWEEN p.period_start AND p.period_end
),
echo_neuro AS (
  SELECT e.patient_id, e.doctor_code, e.outpatient_date
  FROM echo_e AS e
  INNER JOIN neuro_doctors AS d
    ON e.doctor_code = d.doctor_code
)
SELECT
  'doctor_count' AS section,
  CAST(COUNT(*) AS STRING) AS k1,
  '' AS k2,
  '' AS k3
FROM neuro_doctors
UNION ALL
SELECT
  'doctor',
  doctor_code,
  '',
  ''
FROM neuro_doctors
UNION ALL
SELECT
  'patient_doctor',
  patient_id,
  doctor_code,
  CAST(COUNT(*) AS STRING)
FROM echo_neuro
GROUP BY patient_id, doctor_code
ORDER BY section, k1, k2
;
