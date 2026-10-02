BEGIN;

UPDATE public.completion_notification_users
SET enabled_notification = false
WHERE id IN (
  'ff6912e2-004a-4ec5-8bba-1f5dca3e76d7',
  '44f85427-9f50-4470-b35e-a2f9c6622a02',
  'fb76e283-387c-407e-89e8-2a20c25ac8be',
  '655e095e-4c11-4ef4-b2bb-f88eaa97c5f9',
  '1e9d5e62-1c13-4156-b2d4-4cfe1ce8a1be',
  '44e707da-df85-4af4-bdba-86ffcb209f65',
  '1c3af980-440b-4629-babc-bf7d783c1c64',
  '08ea0153-8171-474e-8b45-38e25724a3ee',
  'b8fd438b-e52f-4a4f-b528-2ced768f7453',
  '3cfd622d-ad09-491e-b3df-f716b1a75e2a',
  '6c656269-c496-4b72-99b7-104646bd5ceb',
  '3ec44b16-f423-43d5-bb72-bd4bd252ec3e',
  'cd36911f-6886-46f2-b477-722daff011cf',
  'cdb52513-60b2-49fe-be3a-ec80d54c4e8d',
  '585b4896-1795-4763-b47b-a5f83ca2a5a9',
  'd6127404-48a7-4cbc-a0cd-86cf4f80e555',
  '17966854-1c16-423e-b9de-1b78a6d77f8b',
  'ce63ac72-bf50-43a2-b0c9-0e59e1d78716',
  '454e29e8-7485-4ba9-8d5e-95ca01c3e791',
  '4be13c3c-6f00-4750-97f0-439eb1c0c426',
  'b5024345-9b13-4e1a-b6a8-ab2b948b82c1',
  '2598fa7e-2d82-4d81-94d2-d9c21095f290',
  '548d67e8-378f-4143-8f8b-8f1824293f37',
  'a68398cb-543f-4ee9-9a0f-5bbea5cef4e2',
  '36d8c606-a8fc-4b38-8a1e-bc930ee1b4e5',
  '30631076-df66-46d8-968f-b23b7d00e514',
  '1306ae15-7d6c-45f9-9c2b-92a02c188963',
  '85e3c82c-9547-48b4-b79d-0860296ad7e8',
  'a1d59c63-0f96-48a6-9ea2-e448519f3b49',
  '5d5908b9-5f3d-4ffb-bcf4-37d150e77fd2',
  '376414ce-6976-4cfa-bf8f-697b01237c44',
  '931bf11a-aa0a-4d2a-8b78-4f883233562d',
  'c052cd1d-84d3-4938-86b0-f0bf21d05fd6'
);

-- 更新件数と内容を確認
SELECT id, enabled_notification
FROM public.completion_notification_users
WHERE id IN (
  'ff6912e2-004a-4ec5-8bba-1f5dca3e76d7',
  '44f85427-9f50-4470-b35e-a2f9c6622a02',
  'fb76e283-387c-407e-89e8-2a20c25ac8be',
  '655e095e-4c11-4ef4-b2bb-f88eaa97c5f9',
  '1e9d5e62-1c13-4156-b2d4-4cfe1ce8a1be',
  '44e707da-df85-4af4-bdba-86ffcb209f65',
  '1c3af980-440b-4629-babc-bf7d783c1c64',
  '08ea0153-8171-474e-8b45-38e25724a3ee',
  'b8fd438b-e52f-4a4f-b528-2ced768f7453',
  '3cfd622d-ad09-491e-b3df-f716b1a75e2a',
  '6c656269-c496-4b72-99b7-104646bd5ceb',
  '3ec44b16-f423-43d5-bb72-bd4bd252ec3e',
  'cd36911f-6886-46f2-b477-722daff011cf',
  'cdb52513-60b2-49fe-be3a-ec80d54c4e8d',
  '585b4896-1795-4763-b47b-a5f83ca2a5a9',
  'd6127404-48a7-4cbc-a0cd-86cf4f80e555',
  '17966854-1c16-423e-b9de-1b78a6d77f8b',
  'ce63ac72-bf50-43a2-b0c9-0e59e1d78716',
  '454e29e8-7485-4ba9-8d5e-95ca01c3e791',
  '4be13c3c-6f00-4750-97f0-439eb1c0c426',
  'b5024345-9b13-4e1a-b6a8-ab2b948b82c1',
  '2598fa7e-2d82-4d81-94d2-d9c21095f290',
  '548d67e8-378f-4143-8f8b-8f1824293f37',
  'a68398cb-543f-4ee9-9a0f-5bbea5cef4e2',
  '36d8c606-a8fc-4b38-8a1e-bc930ee1b4e5',
  '30631076-df66-46d8-968f-b23b7d00e514',
  '1306ae15-7d6c-45f9-9c2b-92a02c188963',
  '85e3c82c-9547-48b4-b79d-0860296ad7e8',
  'a1d59c63-0f96-48a6-9ea2-e448519f3b49',
  '5d5908b9-5f3d-4ffb-bcf4-37d150e77fd2',
  '376414ce-6976-4cfa-bf8f-697b01237c44',
  '931bf11a-aa0a-4d2a-8b78-4f883233562d',
  'c052cd1d-84d3-4938-86b0-f0bf21d05fd6'
);

-- 問題なければ:
-- COMMIT;

-- 取り消すなら:
-- ROLLBACK;
