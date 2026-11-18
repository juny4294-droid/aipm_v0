-- 脳神経外科の医師コード数と、160165010 の患者がどの医師に付くか
-- tenant 274 / 2025-10-01〜2026-09-30 / E行

WITH
params AS (
  SELECT
    274 AS tenant_id,
    DATE '2025-10-01' AS period_start,
    DATE '2026-09-30' AS period_end
),
master AS (
  SELECT
    d.doctor_code,
    d.department_name
  FROM `medup-foro.dpc_patient_records_prd.dbt_int_doctor_department` AS d
  CROSS JOIN params AS p
  WHERE SAFE_CAST(d.tenant_id AS INT64) = p.tenant_id
    AND d.department_name LIKE '%脳神%'
),
neuro AS (
  SELECT DISTINCT doctor_code
  FROM master
  WHERE department_name = '脳神経外科'
),
echo AS (
  SELECT
    CAST(SAFE_CAST(ef.patient_id AS INT64) AS STRING) AS patient_id,
    ef.doctor_code
  FROM `medup-foro.dpc_patient_records_prd.outpatient_ef` AS ef
  CROSS JOIN params AS p
  WHERE ef.tenant_id = p.tenant_id
    AND ef.data_type != 'SY'
    AND ef.action_detail_number = 0
    AND ef.receipt_code = '160165010'
    AND ef.outpatient_date.value BETWEEN p.period_start AND p.period_end
),
echo_neuro AS (
  SELECT e.patient_id, e.doctor_code
  FROM echo AS e
  INNER JOIN neuro AS n
    ON e.doctor_code = n.doctor_code
)
SELECT
  'master_like' AS section,
  department_name AS k1,
  CAST(COUNT(DISTINCT doctor_code) AS STRING) AS k2,
  CAST(COUNT(*) AS STRING) AS k3
FROM master
GROUP BY department_name
UNION ALL
SELECT
  'by_doctor',
  n.doctor_code,
  CAST(COUNT(DISTINCT e.patient_id) AS STRING),
  CAST(COUNT(e.patient_id) AS STRING)
FROM neuro AS n
LEFT JOIN echo_neuro AS e
  ON n.doctor_code = e.doctor_code
GROUP BY n.doctor_code
UNION ALL
SELECT
  'patients',
  CAST(COUNT(DISTINCT patient_id) AS STRING),
  CAST(COUNT(DISTINCT doctor_code) AS STRING),
  ''
FROM echo_neuro
ORDER BY section, k1
;
