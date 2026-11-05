-- 脳神経外科｜逆紹介候補抽出（鳥取県立中央 / tenant 274）
-- 条件版: 2026-11-05 N4追加後。次回以降はこれをコピーし、params の日付だけ変える
-- このファイルの期間: 2025-10-01 〜 2026-09-30（N4追加時の比較期間）
-- 対象: N1∧N2∧(N3∨(N4_1∧N4_2))
--   N4_1 脳外の最大行為 = 5.検査（US・XP含む）
--   N4_2 脳外受診に 160165010（超音波検査・断層撮影法・その他）が1回以上
-- NX3: 適用しない（空集合）。予約JOINはコメント残置
-- 修正前: documents/4_executing/queries/脳神経外科_N4追加前/

WITH
params AS (
  SELECT
    274 AS tenant_id,
    DATE '2025-10-01' AS period_start,
    DATE '2026-09-30' AS period_end,
    '脳神経外科' AS target_department_name,
    DATE_SUB(DATE '2026-09-30', INTERVAL 5 YEAR) AS sah_lookback_start,
    '160165010' AS carotid_echo_code
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

-- 脳外の受診（E行と明細）。N4_2 は明細行にしか無い場合も拾う
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

-- N4_2: 脳外受診に頸動脈エコー（超音波検査・断層撮影法・その他）
echo_patients AS (
  SELECT DISTINCT patient_id
  FROM neuro_ef
  CROSS JOIN params AS p
  WHERE receipt_code = p.carotid_echo_code
),

-- N4_1 用。最大行為は整形・泌尿と同じ優先順位で、脳外のE行だけから付ける
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

-- N4_1: 最大行為が検査
n4_exam_max AS (
  SELECT patient_id
  FROM categorized
  WHERE medical_service_category = '5.検査（US・XP含む）'
),

-- N4 = N4_1 ∧ N4_2
n4_patients AS (
  SELECT e.patient_id
  FROM echo_patients AS e
  INNER JOIN n4_exam_max AS x
    USING (patient_id)
),

-- N1∧N2∧N3
n3_in_neuro AS (
  SELECT n.patient_id
  FROM neuro_patients AS n
  INNER JOIN mri_patients AS m
    USING (patient_id)
),

-- 対象: N1∧N2∧(N3∨(N4_1∧N4_2))
target_patients AS (
  SELECT patient_id FROM n3_in_neuro
  UNION DISTINCT
  SELECT patient_id FROM n4_patients
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
    (SELECT COUNT(*) FROM n3_in_neuro) AS n_n3,
    (SELECT COUNT(*) FROM n4_patients) AS n_n4,
    (SELECT COUNT(*) FROM target_patients) AS n_target,
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
