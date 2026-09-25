SELECT
  t.patient_id,
  t.medical_service_category,
  t.visit_count_in_specialty,
  IF(ox2.patient_id IS NOT NULL, 1, 0) AS ox2_noninvasive_reduction_flag,
  IF(ox3.patient_id IS NOT NULL, 1, 0) AS ox3_reverse_referred_flag
FROM target_patients AS t
LEFT JOIN ox2_noninvasive_reduction AS ox2
  USING (patient_id)
LEFT JOIN ox3_reverse_referred AS ox3
  USING (patient_id)
WHERE ox2.patient_id IS NULL
  AND ox3.patient_id IS NULL
ORDER BY t.patient_id
;