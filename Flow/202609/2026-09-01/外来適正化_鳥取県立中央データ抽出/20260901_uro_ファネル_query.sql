WITH
params AS (
  SELECT
    274 AS tenant_id,
    DATE '2025-08-01' AS period_start,
    DATE '2026-07-31' AS period_end,
    '泌尿器科' AS target_department_name,
    75462 AS tottori_univ_medical_institution_id,
    DATE_SUB(DATE '2026-07-31', INTERVAL 5 YEAR) AS prostate_surgery_lookback_start
),
mri_codes AS (
  SELECT code FROM UNNEST(['170020110', '170033510']) AS code
),
uro_doctors AS (
  SELECT
    SAFE_CAST(d.tenant_id AS INT64) AS tenant_id,
    d.doctor_code,
    d.department_name
  FROM `medup-foro.dpc_patient_records_prd.dbt_int_doctor_department` AS d
  CROSS JOIN params AS p
  WHERE SAFE_CAST(d.tenant_id AS INT64) = p.tenant_id
    AND d.department_name = p.target_department_name
),
uro_ef AS (
  SELECT
    CAST(SAFE_CAST(ef.patient_id AS INT64) AS STRING) AS patient_id,
    ef.outpatient_date.value AS outpatient_date,
    ef.receipt_code
  FROM `medup-foro.dpc_patient_records_prd.outpatient_ef` AS ef
  INNER JOIN uro_doctors AS ud
    ON ef.doctor_code = ud.doctor_code
   AND SAFE_CAST(ef.tenant_id AS INT64) = ud.tenant_id
  CROSS JOIN params AS p
  WHERE ef.tenant_id = p.tenant_id
    AND ef.data_type != 'SY'
    AND ef.action_detail_number = 0
    AND ef.outpatient_date.value BETWEEN p.period_start AND p.period_end
),
ef_period AS (
  SELECT
    CAST(SAFE_CAST(ef.patient_id AS INT64) AS STRING) AS patient_id,
    IFNULL(d.department_name, '未割当') AS department_name,
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
patient_flags AS (
  SELECT
    patient_id,
    COUNT(DISTINCT outpatient_date) AS visit_count_in_specialty,
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
        ) THEN 1 ELSE 0
      END
    ) AS ct_imaging_flag,
    MAX(CASE WHEN STARTS_WITH(receipt_code, '170') THEN 1 ELSE 0 END) AS imaging_flag,
    MAX(CASE WHEN STARTS_WITH(receipt_code, '160') THEN 1 ELSE 0 END) AS exam_flag,
    MAX(CASE WHEN STARTS_WITH(receipt_code, '12') THEN 1 ELSE 0 END) AS medication_flag,
    MAX(CASE WHEN receipt_code IN ('180756010', '180024710') THEN 1 ELSE 0 END) AS rehabilitation_flag
  FROM uro_ef
  GROUP BY patient_id
),
admission_uro AS (
  SELECT DISTINCT CAST(SAFE_CAST(h.patient_number AS INT64) AS STRING) AS patient_id
  FROM `medup-foro.foro_prd.public_hospital_admissions` AS h
  LEFT JOIN `medup-foro.foro_prd.public_dpc_specialty_codes` AS c
    ON c.code = h.dpc_specialty_code
  CROSS JOIN params AS p
  WHERE h.tenant_id = p.tenant_id
    AND (c.name = p.target_department_name OR c.name LIKE '%泌尿%')
    AND (
      h.admission_started_on BETWEEN p.period_start AND p.period_end
      OR h.admission_ended_on BETWEEN p.period_start AND p.period_end
    )
),
categorized AS (
  SELECT
    f.patient_id,
    f.visit_count_in_specialty,
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
  LEFT JOIN admission_uro AS a USING (patient_id)
),
uro_patients AS (
  SELECT DISTINCT patient_id FROM uro_ef
),
target_patients AS (
  SELECT *
  FROM categorized
  WHERE
    (medical_service_category = '4.CT/MRI' AND visit_count_in_specialty <= 2)
    OR (medical_service_category = '5.検査（US・XP含む）' AND visit_count_in_specialty <= 5)
    OR medical_service_category IN ('6.投薬', '8.再診')
),
ux1 AS (
  SELECT DISTINCT t.patient_id
  FROM target_patients AS t
  INNER JOIN ef_period AS e USING (patient_id)
  CROSS JOIN params AS p
  WHERE e.department_name != p.target_department_name
),
ux2 AS (
  SELECT DISTINCT t.patient_id
  FROM target_patients AS t
  INNER JOIN ef_period AS e USING (patient_id)
  INNER JOIN mri_codes AS m ON e.receipt_code = m.code
),
ux3 AS (
  SELECT DISTINCT CAST(SAFE_CAST(r.patient_id AS INT64) AS STRING) AS patient_id
  FROM `medup-foro.foro_prd.public_referrals` AS r
  INNER JOIN `medup-foro.foro_prd.public_own_departments` AS dept
    ON dept.id = r.specialty_id
  INNER JOIN `medup-foro.foro_prd.public_own_department_tenants` AS odt
    ON odt.own_department_id = dept.id AND odt.tenant_id = r.tenant_id
  CROSS JOIN params AS p
  WHERE r.tenant_id = p.tenant_id
    AND dept.name = p.target_department_name
    AND r.medical_institution_id_from = p.tottori_univ_medical_institution_id
),
ux4 AS (
  SELECT DISTINCT CAST(SAFE_CAST(h.patient_number AS INT64) AS STRING) AS patient_id
  FROM `medup-foro.foro_prd.public_hospital_admissions` AS h
  CROSS JOIN params AS p
  WHERE h.tenant_id = p.tenant_id
    AND h.dpc_code IS NOT NULL
    AND STARTS_WITH(h.dpc_code, '110080')
    AND h.kcode_operation_1 IS NOT NULL
    AND STARTS_WITH(h.kcode_operation_1, 'K843')
    AND h.admission_ended_on > p.prostate_surgery_lookback_start
    AND h.admission_ended_on <= p.period_end
),
ux6 AS (
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
    (SELECT COUNT(*) FROM uro_patients) AS n_u1_u2_uro,
    (SELECT COUNT(*) FROM target_patients) AS n_u3_u5_target,
    COUNTIF(ux1.patient_id IS NOT NULL) AS n_ux1,
    COUNTIF(ux2.patient_id IS NOT NULL) AS n_ux2,
    COUNTIF(ux3.patient_id IS NOT NULL) AS n_ux3,
    COUNTIF(ux4.patient_id IS NOT NULL) AS n_ux4,
    COUNTIF(ux6.patient_id IS NOT NULL) AS n_ux6,
    COUNTIF(
      ux1.patient_id IS NULL
      AND ux2.patient_id IS NULL
      AND ux3.patient_id IS NULL
      AND ux4.patient_id IS NULL
      AND ux6.patient_id IS NULL
    ) AS n_final_candidates
  FROM target_patients AS t
  LEFT JOIN ux1 USING (patient_id)
  LEFT JOIN ux2 USING (patient_id)
  LEFT JOIN ux3 USING (patient_id)
  LEFT JOIN ux4 USING (patient_id)
  LEFT JOIN ux6 USING (patient_id)
)
SELECT * FROM funnel;
