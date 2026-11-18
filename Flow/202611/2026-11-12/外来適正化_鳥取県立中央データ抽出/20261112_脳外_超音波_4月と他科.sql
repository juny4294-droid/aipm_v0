-- 2026-04 の欠落と、160165010 が脳外以外に付いていないかを見る

WITH
params AS (
  SELECT
    274 AS tenant_id,
    DATE '2025-10-01' AS period_start,
    DATE '2026-09-30' AS period_end,
    '脳神経外科' AS target_department_name
),
ef AS (
  SELECT
    CAST(SAFE_CAST(ef.patient_id AS INT64) AS STRING) AS patient_id,
    ef.outpatient_date.value AS outpatient_date,
    ef.receipt_code,
    ef.action_detail_number,
    ef.doctor_code,
    IFNULL(d.department_name, '未割当') AS department_name
  FROM `medup-foro.dpc_patient_records_prd.outpatient_ef` AS ef
  LEFT JOIN `medup-foro.dpc_patient_records_prd.dbt_int_doctor_department` AS d
    ON ef.doctor_code = d.doctor_code
   AND SAFE_CAST(ef.tenant_id AS INT64) = SAFE_CAST(d.tenant_id AS INT64)
  CROSS JOIN params AS p
  WHERE ef.tenant_id = p.tenant_id
    AND ef.data_type != 'SY'
    AND ef.outpatient_date.value BETWEEN p.period_start AND p.period_end
),
april AS (
  SELECT
    '1_2026年4月' AS section,
    CAST(COUNTIF(action_detail_number = 0) AS STRING) AS k1,
    CAST(COUNTIF(action_detail_number > 0) AS STRING) AS k2,
    CAST(COUNTIF(receipt_code = '160165010') AS STRING) AS k3,
    '' AS k4,
    '' AS k5
  FROM ef
  WHERE outpatient_date BETWEEN DATE '2026-04-01' AND DATE '2026-04-30'
),
neuro_patients AS (
  SELECT DISTINCT patient_id
  FROM ef
  CROSS JOIN params AS p
  WHERE department_name = p.target_department_name
    AND action_detail_number = 0
),
echo_place AS (
  SELECT
    e.patient_id,
    MAX(IF(e.department_name = '脳神経外科', 1, 0)) AS on_neuro,
    MAX(IF(e.department_name != '脳神経外科', 1, 0)) AS on_other
  FROM ef AS e
  INNER JOIN neuro_patients AS n
    USING (patient_id)
  WHERE e.receipt_code = '160165010'
  GROUP BY e.patient_id
),
echo_place_sum AS (
  SELECT
    '2_脳外患者の160165010の付き方' AS section,
    CAST(COUNTIF(on_neuro = 1 AND on_other = 0) AS STRING) AS k1,
    CAST(COUNTIF(on_neuro = 1 AND on_other = 1) AS STRING) AS k2,
    CAST(COUNTIF(on_neuro = 0 AND on_other = 1) AS STRING) AS k3,
    CAST(COUNT(*) AS STRING) AS k4,
    '' AS k5
  FROM echo_place
),
other_dept_for_neuro_pts AS (
  SELECT
    '3_脳外患者で他科に付いた160165010' AS section,
    e.department_name AS k1,
    CAST(COUNT(DISTINCT e.patient_id) AS STRING) AS k2,
    '' AS k3,
    '' AS k4,
    '' AS k5
  FROM ef AS e
  INNER JOIN neuro_patients AS n
    USING (patient_id)
  WHERE e.receipt_code = '160165010'
    AND e.department_name != '脳神経外科'
  GROUP BY e.department_name
),
addon AS (
  SELECT
    '4_160072370と160165010' AS section,
    CAST(COUNT(DISTINCT IF(receipt_code = '160072370', patient_id, NULL)) AS STRING) AS k1,
    CAST(COUNT(DISTINCT IF(receipt_code = '160165010', patient_id, NULL)) AS STRING) AS k2,
    CAST(COUNT(DISTINCT IF(
      receipt_code = '160072370'
      AND patient_id IN (
        SELECT patient_id FROM ef
        WHERE receipt_code = '160165010' AND department_name = '脳神経外科'
      ),
      patient_id, NULL
    )) AS STRING) AS k3,
    '' AS k4,
    '' AS k5
  FROM ef
  WHERE department_name = '脳神経外科'
    AND receipt_code IN ('160072370', '160165010')
),
unassigned_doctors AS (
  SELECT
    '5_未割当で160165010の医師' AS section,
    e.doctor_code AS k1,
    CAST(COUNT(DISTINCT e.patient_id) AS STRING) AS k2,
    CAST(COUNT(*) AS STRING) AS k3,
    '' AS k4,
    '' AS k5
  FROM ef AS e
  WHERE e.receipt_code = '160165010'
    AND e.department_name = '未割当'
    AND e.action_detail_number = 0
  GROUP BY e.doctor_code
  QUALIFY ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT e.patient_id) DESC) <= 15
)
SELECT * FROM april
UNION ALL SELECT * FROM echo_place_sum
UNION ALL SELECT * FROM other_dept_for_neuro_pts
UNION ALL SELECT * FROM addon
UNION ALL SELECT * FROM unassigned_doctors
ORDER BY section, k2 DESC
;
