SELECT
  t.patient_id,
  t.medical_service_category,
  t.visit_count_in_specialty,
  IF(ux1.patient_id IS NOT NULL, 1, 0) AS ux1_multi_dept_flag,
  IF(ux2.patient_id IS NOT NULL, 1, 0) AS ux2_mri_flag,
  IF(ux3.patient_id IS NOT NULL, 1, 0) AS ux3_tottori_univ_flag,
  IF(ux4.patient_id IS NOT NULL, 1, 0) AS ux4_prostate_surgery_flag,
  IF(ux6.patient_id IS NOT NULL, 1, 0) AS ux6_reverse_referred_flag
FROM target_patients AS t
LEFT JOIN ux1_multi_dept AS ux1 USING (patient_id)
LEFT JOIN ux2_mri AS ux2 USING (patient_id)
LEFT JOIN ux3_tottori_univ AS ux3 USING (patient_id)
LEFT JOIN ux4_prostate_surgery AS ux4 USING (patient_id)
LEFT JOIN ux6_reverse_referred AS ux6 USING (patient_id)
WHERE ux1.patient_id IS NULL
  AND ux2.patient_id IS NULL
  AND ux3.patient_id IS NULL
  AND ux4.patient_id IS NULL
  AND ux6.patient_id IS NULL
ORDER BY t.patient_id
;