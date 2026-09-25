SELECT
  t.patient_id,
  IF(nx1.patient_id IS NOT NULL, 1, 0) AS nx1_multi_dept_flag,
  IF(nx2.patient_id IS NOT NULL, 1, 0) AS nx2_ct_flag,
  IF(nx3.patient_id IS NOT NULL, 1, 0) AS nx3_jinbu_flag,
  IF(nx4.patient_id IS NOT NULL, 1, 0) AS nx4_vascular_or_platelet_flag,
  IF(nx5.patient_id IS NOT NULL, 1, 0) AS nx5_contrast_mri_flag,
  IF(nx6.patient_id IS NOT NULL, 1, 0) AS nx6_epilepsy_flag,
  IF(nx7.patient_id IS NOT NULL, 1, 0) AS nx7_sah_flag,
  IF(nx8.patient_id IS NOT NULL, 1, 0) AS nx8_reverse_referred_flag
FROM target_patients AS t
LEFT JOIN nx1_multi_dept AS nx1 USING (patient_id)
LEFT JOIN nx2_ct AS nx2 USING (patient_id)
LEFT JOIN nx3_jinbu AS nx3 USING (patient_id)
LEFT JOIN nx4_vascular_or_platelet AS nx4 USING (patient_id)
LEFT JOIN nx5_contrast_mri AS nx5 USING (patient_id)
LEFT JOIN nx6_epilepsy AS nx6 USING (patient_id)
LEFT JOIN nx7_sah AS nx7 USING (patient_id)
LEFT JOIN nx8_reverse_referred AS nx8 USING (patient_id)
WHERE nx1.patient_id IS NULL
  AND nx2.patient_id IS NULL
  AND nx3.patient_id IS NULL
  AND nx4.patient_id IS NULL
  AND nx5.patient_id IS NULL
  AND nx6.patient_id IS NULL
  AND nx7.patient_id IS NULL
  AND nx8.patient_id IS NULL
ORDER BY t.patient_id
;