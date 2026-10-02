-- 脳神経外科｜逆紹介候補抽出（鳥取県立中央 / tenant 274）
-- 実行日: 2026-09-30
-- 期間: 2025-09-01 〜 2026-08-31
-- NX3: 適用しない（空集合）。予約JOINはコメント残置
-- NX8: public_reverse_referrals は 2026-07-31 まで（8月分はユーザー提出待ち）
-- 正本: 20260826_脳外_逆紹介候補抽出.sql

WITH
params AS (
  SELECT
    274 AS tenant_id,
    DATE '2025-09-01' AS period_start,
    DATE '2026-08-31' AS period_end,
    '脳神経外科' AS target_department_name,
    DATE_SUB(DATE '2026-08-31', INTERVAL 5 YEAR) AS sah_lookback_start
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
  -- 2026-09-30: 適用しないのが正。空集合。本体はリストA側コメントに残置
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
