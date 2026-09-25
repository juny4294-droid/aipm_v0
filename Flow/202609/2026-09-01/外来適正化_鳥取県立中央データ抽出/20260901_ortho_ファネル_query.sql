WITH
params AS (
  SELECT
    274 AS tenant_id,
    DATE '2025-08-01' AS period_start,
    DATE '2026-07-31' AS period_end,
    '整形外科' AS target_department_name
),
ortho_doctors AS (
  SELECT
    SAFE_CAST(d.tenant_id AS INT64) AS tenant_id,
    d.doctor_code,
    d.department_name
  FROM `medup-foro.dpc_patient_records_prd.dbt_int_doctor_department` AS d
  CROSS JOIN params AS p
  WHERE SAFE_CAST(d.tenant_id AS INT64) = p.tenant_id
    AND d.department_name = p.target_department_name
),
ortho_ef AS (
  SELECT
    CAST(SAFE_CAST(ef.patient_id AS INT64) AS STRING) AS patient_id,
    ef.outpatient_date.value AS outpatient_date,
    ef.receipt_code
  FROM `medup-foro.dpc_patient_records_prd.outpatient_ef` AS ef
  INNER JOIN ortho_doctors AS od
    ON ef.doctor_code = od.doctor_code
   AND SAFE_CAST(ef.tenant_id AS INT64) = od.tenant_id
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
    MAX(CASE WHEN receipt_code IN ('170033410','170012070','170011810','170035010','170020110','170020470') THEN 1 ELSE 0 END) AS ct_imaging_flag,
    MAX(CASE WHEN STARTS_WITH(receipt_code, '170') THEN 1 ELSE 0 END) AS imaging_flag,
    MAX(CASE WHEN STARTS_WITH(receipt_code, '160') THEN 1 ELSE 0 END) AS exam_flag,
    MAX(CASE WHEN STARTS_WITH(receipt_code, '12') THEN 1 ELSE 0 END) AS medication_flag,
    MAX(CASE WHEN receipt_code IN ('180756010','180024710') THEN 1 ELSE 0 END) AS rehabilitation_flag
  FROM ortho_ef
  GROUP BY patient_id
),
admission_ortho AS (
  SELECT DISTINCT CAST(SAFE_CAST(h.patient_number AS INT64) AS STRING) AS patient_id
  FROM `medup-foro.foro_prd.public_hospital_admissions` AS h
  LEFT JOIN `medup-foro.foro_prd.public_dpc_specialty_codes` AS c
    ON c.code = h.dpc_specialty_code
  CROSS JOIN params AS p
  WHERE h.tenant_id = p.tenant_id
    AND (c.name = p.target_department_name OR c.name LIKE '%整形%')
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
      WHEN f.follow_up_visit_flag = 1 AND (f.imaging_flag = 1 OR f.exam_flag = 1)
        THEN '5.検査（US・XP含む）'
      WHEN f.follow_up_visit_flag = 1 AND f.medication_flag = 1 THEN '6.投薬'
      WHEN f.follow_up_visit_flag = 1 AND f.rehabilitation_flag = 1 THEN '7.リハ'
      WHEN f.follow_up_visit_flag = 1 THEN '8.再診'
      ELSE '9.その他'
    END AS medical_service_category
  FROM patient_flags AS f
  LEFT JOIN admission_ortho AS a USING (patient_id)
),
ox2 AS (
  SELECT DISTINCT patient_id
  FROM ortho_ef
  WHERE receipt_code IN (
    '150016510','150016610','150016710','150016810','150016910',
    '150017010','150017110','150017210','150017310','150060410',
    '150114610','150115010',
    '150033810','150033910','150034010','150034110','150034210',
    '150034310','150034410','150034510','150034610','150034710',
    '150035050','150035110','150114810'
  )
),
ox3 AS (
  SELECT DISTINCT CAST(SAFE_CAST(r.patient_id AS INT64) AS STRING) AS patient_id
  FROM `medup-foro.foro_prd.public_reverse_referrals` AS r
  INNER JOIN `medup-foro.foro_prd.public_own_departments` AS dept
    ON dept.id = r.specialty_id
  INNER JOIN `medup-foro.foro_prd.public_own_department_tenants` AS odt
    ON odt.own_department_id = dept.id
   AND odt.tenant_id = r.tenant_id
  CROSS JOIN params AS p
  WHERE r.tenant_id = p.tenant_id
    AND dept.name = p.target_department_name
    AND r.reverse_referral_date BETWEEN p.period_start AND p.period_end
),
funnel AS (
  SELECT
    (SELECT COUNT(DISTINCT patient_id) FROM ortho_ef) AS n_o1_o2_ortho_visits,
    (SELECT COUNT(*) FROM categorized WHERE medical_service_category NOT IN ('1.入院','2.初診')) AS n_o3_target,
    (SELECT COUNT(*) FROM categorized c WHERE medical_service_category NOT IN ('1.入院','2.初診') AND EXISTS (SELECT 1 FROM ox2 WHERE ox2.patient_id = c.patient_id)) AS n_ox2,
    (SELECT COUNT(*) FROM categorized c WHERE medical_service_category NOT IN ('1.入院','2.初診') AND EXISTS (SELECT 1 FROM ox3 WHERE ox3.patient_id = c.patient_id)) AS n_ox3,
    (
      SELECT COUNT(*)
      FROM categorized c
      WHERE medical_service_category NOT IN ('1.入院','2.初診')
        AND NOT EXISTS (SELECT 1 FROM ox2 WHERE ox2.patient_id = c.patient_id)
        AND NOT EXISTS (SELECT 1 FROM ox3 WHERE ox3.patient_id = c.patient_id)
    ) AS n_final_candidates
)
SELECT * FROM funnel;
