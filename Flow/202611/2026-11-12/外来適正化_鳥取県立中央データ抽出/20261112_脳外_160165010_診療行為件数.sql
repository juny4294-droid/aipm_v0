-- 160165010 を診療科条件なしで、診療行為（E行）単位に数える
-- 期間: 2025-10-01 〜 2026-09-30 / tenant 274
-- 明細行は同じ行為の内訳なので件数には入れない

WITH
ef AS (
  SELECT
    CAST(SAFE_CAST(ef.patient_id AS INT64) AS STRING) AS patient_id,
    ef.outpatient_date.value AS outpatient_date,
    ef.action_detail_number,
    ef.action_name,
    IFNULL(SAFE_CAST(ef.number_of_action AS INT64), 0) AS number_of_action,
    IFNULL(d.department_name, '未割当') AS department_name
  FROM `medup-foro.dpc_patient_records_prd.outpatient_ef` AS ef
  LEFT JOIN `medup-foro.dpc_patient_records_prd.dbt_int_doctor_department` AS d
    ON ef.doctor_code = d.doctor_code
   AND SAFE_CAST(ef.tenant_id AS INT64) = SAFE_CAST(d.tenant_id AS INT64)
  WHERE ef.tenant_id = 274
    AND ef.data_type != 'SY'
    AND ef.receipt_code = '160165010'
    AND ef.outpatient_date.value BETWEEN DATE '2025-10-01' AND DATE '2026-09-30'
),
by_dept AS (
  SELECT
    department_name,
    COUNTIF(action_detail_number = 0) AS e_rows,
    SUM(IF(action_detail_number = 0, number_of_action, 0)) AS action_count,
    COUNT(DISTINCT IF(action_detail_number = 0, patient_id, NULL)) AS patients,
    COUNTIF(action_detail_number > 0) AS detail_rows
  FROM ef
  GROUP BY department_name
),
totals AS (
  SELECT
    '合計' AS department_name,
    COUNTIF(action_detail_number = 0) AS e_rows,
    SUM(IF(action_detail_number = 0, number_of_action, 0)) AS action_count,
    COUNT(DISTINCT IF(action_detail_number = 0, patient_id, NULL)) AS patients,
    COUNTIF(action_detail_number > 0) AS detail_rows
  FROM ef
)
SELECT * FROM by_dept
UNION ALL
SELECT * FROM totals
ORDER BY
  CASE department_name WHEN '合計' THEN 1 ELSE 0 END,
  e_rows DESC
;
