-- 脳外を受診した日に、160165010 が別の医師・診療科に付いていないか

WITH
params AS (
  SELECT
    274 AS tenant_id,
    DATE '2025-10-01' AS period_start,
    DATE '2026-09-30' AS period_end
),
ef AS (
  SELECT
    CAST(SAFE_CAST(ef.patient_id AS INT64) AS STRING) AS patient_id,
    ef.outpatient_date.value AS outpatient_date,
    ef.receipt_code,
    ef.doctor_code,
    IFNULL(d.department_name, '未割当') AS department_name
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
neuro_days AS (
  SELECT DISTINCT patient_id, outpatient_date
  FROM ef
  WHERE department_name = '脳神経外科'
),
echo_other AS (
  SELECT
    e.patient_id,
    e.outpatient_date,
    e.department_name,
    e.doctor_code
  FROM ef AS e
  INNER JOIN neuro_days AS n
    USING (patient_id, outpatient_date)
  WHERE e.receipt_code = '160165010'
    AND e.department_name != '脳神経外科'
)
SELECT
  department_name,
  doctor_code,
  COUNT(DISTINCT patient_id) AS patients,
  COUNT(*) AS n_rows
FROM echo_other
GROUP BY department_name, doctor_code
ORDER BY patients DESC
;
