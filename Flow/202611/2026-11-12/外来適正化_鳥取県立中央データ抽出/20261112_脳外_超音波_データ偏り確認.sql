-- 鳥取県立中央 tenant 274
-- 160165010 の91人が、期間の片寄りやコードの抜けで少なく見えていないかを確認する
-- 期間の本体は 2025-10-01〜2026-09-30。月次の埋まりは前後も含めて見る

WITH
params AS (
  SELECT
    274 AS tenant_id,
    DATE '2025-10-01' AS period_start,
    DATE '2026-09-30' AS period_end,
    '脳神経外科' AS target_department_name
),
us_codes AS (
  SELECT code, label FROM UNNEST([
    STRUCT('160164970' AS code, '血管内超音波検査加算' AS label),
    STRUCT('160198470', '心腔内超音波検査加算'),
    STRUCT('160072110', 'Aモード法'),
    STRUCT('160072210', '断層・胸腹部'),
    STRUCT('160165010', '断層・その他'),
    STRUCT('160213010', '断層・下肢血管'),
    STRUCT('160218310', '断層・訪問診療'),
    STRUCT('160072450', '心臓以外・断層とMモード'),
    STRUCT('160072510', '経胸壁心エコー'),
    STRUCT('160072610', 'Mモード'),
    STRUCT('160072750', '心臓以外・Mモード'),
    STRUCT('160160410', '経食道心エコー'),
    STRUCT('160186610', '胎児心エコー'),
    STRUCT('160198810', '負荷心エコー'),
    STRUCT('160213170', '胎児心エコー診断加算'),
    STRUCT('160072910', 'ドプラ・胎児心音'),
    STRUCT('160147110', 'ドプラ・脳動脈連続'),
    STRUCT('160147210', 'ドプラ・脳動脈マッピング'),
    STRUCT('160150050', 'ドプラ・末梢血管'),
    STRUCT('160161710', '血管内超音波法'),
    STRUCT('160182970', '造影剤使用加算'),
    STRUCT('160231810', '前立腺針生検・融合画像')
  ])
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
    AND ef.outpatient_date.value BETWEEN DATE '2025-04-01' AND DATE '2026-10-31'
),
monthly_volume AS (
  SELECT
    '1_月次E行' AS section,
    FORMAT_DATE('%Y-%m', outpatient_date) AS k1,
    CAST(COUNTIF(action_detail_number = 0) AS STRING) AS k2,
    CAST(COUNT(DISTINCT IF(action_detail_number = 0, outpatient_date, NULL)) AS STRING) AS k3,
    CAST(COUNTIF(action_detail_number > 0) AS STRING) AS k4,
    '' AS k5
  FROM ef
  GROUP BY k1
),
code_by_dept AS (
  SELECT
    '2_コード別診療科' AS section,
    u.label AS k1,
    e.department_name AS k2,
    CAST(COUNT(DISTINCT e.patient_id) AS STRING) AS k3,
    CAST(COUNTIF(e.action_detail_number = 0) AS STRING) AS k4,
    CAST(COUNTIF(e.action_detail_number > 0) AS STRING) AS k5
  FROM ef AS e
  INNER JOIN us_codes AS u
    ON e.receipt_code = u.code
  CROSS JOIN params AS p
  WHERE e.outpatient_date BETWEEN p.period_start AND p.period_end
  GROUP BY k1, k2
),
echo_month_neuro AS (
  SELECT
    '3_脳外160165010の月' AS section,
    FORMAT_DATE('%Y-%m', e.outpatient_date) AS k1,
    CAST(COUNT(DISTINCT e.patient_id) AS STRING) AS k2,
    CAST(COUNTIF(e.action_detail_number = 0) AS STRING) AS k3,
    CAST(COUNTIF(e.action_detail_number > 0) AS STRING) AS k4,
    '' AS k5
  FROM ef AS e
  CROSS JOIN params AS p
  WHERE e.receipt_code = '160165010'
    AND e.department_name = p.target_department_name
    AND e.outpatient_date BETWEEN p.period_start AND p.period_end
  GROUP BY k1
),
echo_span AS (
  SELECT
    '4_脳外160165010の幅' AS section,
    CAST(COUNT(DISTINCT e.patient_id) AS STRING) AS k1,
    CAST(MIN(e.outpatient_date) AS STRING) AS k2,
    CAST(MAX(e.outpatient_date) AS STRING) AS k3,
    CAST(COUNT(DISTINCT e.outpatient_date) AS STRING) AS k4,
    CAST(COUNT(DISTINCT FORMAT_DATE('%Y-%m', e.outpatient_date)) AS STRING) AS k5
  FROM ef AS e
  CROSS JOIN params AS p
  WHERE e.receipt_code = '160165010'
    AND e.department_name = p.target_department_name
    AND e.outpatient_date BETWEEN p.period_start AND p.period_end
),
neuro_160_top AS (
  SELECT
    '5_脳外の160系上位' AS section,
    e.receipt_code AS k1,
    CAST(COUNT(DISTINCT e.patient_id) AS STRING) AS k2,
    CAST(COUNT(*) AS STRING) AS k3,
    '' AS k4,
    '' AS k5
  FROM ef AS e
  CROSS JOIN params AS p
  WHERE e.department_name = p.target_department_name
    AND e.outpatient_date BETWEEN p.period_start AND p.period_end
    AND STARTS_WITH(e.receipt_code, '160')
  GROUP BY e.receipt_code
  QUALIFY ROW_NUMBER() OVER (ORDER BY COUNT(DISTINCT e.patient_id) DESC) <= 25
)
SELECT * FROM monthly_volume
UNION ALL SELECT * FROM code_by_dept
UNION ALL SELECT * FROM echo_month_neuro
UNION ALL SELECT * FROM echo_span
UNION ALL SELECT * FROM neuro_160_top
ORDER BY section, k1
;
