BEGIN;

INSERT INTO public.completion_notification_users
(id, tenant_id, "name", honorific, email, enabled_notification, last_sent_at, created_at, updated_at, "order")
VALUES
  (gen_random_uuid(), 11, '緒方', '様', 'hiroshi-ogata@saiseikaikumamoto.jp', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1),
  (gen_random_uuid(), 60, '望月', '様', 'k-mochizuki@kkr-smc.com', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1),
  (gen_random_uuid(), 162, '鴨川', '様', 'yasuhiko_kamogawa@kcho.jp', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1),
  (gen_random_uuid(), 89, '村上聡', '様', 's_murakami@jikei.ac.jp', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1),
  (gen_random_uuid(), 78, '桜井伸', '様', 'sakurai-shin@rakuwa.or.jp', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1),
  (gen_random_uuid(), 121, '白石航平', '様', 'shiraishi.kohei@jp.panasonic.com', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 2),
  (gen_random_uuid(), 143, '山本佳宣', '様', 'yoshinobu.ya@hp.pref.hyogo.jp', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1),
  (gen_random_uuid(), 143, '藤本美生', '様', 'Mio_Fujimoto@pref.hyogo.lg.jp', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 2),
  (gen_random_uuid(), 167, '長谷山義勝', '様', 'y-hase@teikyo-u.ac.jp', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1),
  (gen_random_uuid(), 105, '縣史樹', '様', 'agata_fumiki@gm.shinshu-u.ac.jp', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1),
  (gen_random_uuid(), 70, '大杉寬子', '様', 'a294097@ych.or.jp', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1),
  (gen_random_uuid(), 170, '池間みずえ', '様', 'ikema.tomishiro.hp@gmail.com', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1),
  (gen_random_uuid(), 170, '地域連携室', '様', 'chiiki@yuuai.or.jp', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 2),
  (gen_random_uuid(), 274, '皆川昇司', '様', 'minagawas@pref.tottori.lg.jp', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 2),
  (gen_random_uuid(), 274, '建部茂', '様', 'tatebes@tp-ch.jp', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1),
  (gen_random_uuid(), 274, '橋本美由紀', '様', 'zenporenkei@tp-ch.jp', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 3),
  (gen_random_uuid(), 274, '大久保', '様', 'ookuboy@pref.tottori.lg.jp', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 4),
  (gen_random_uuid(), 171, '野澤正充', '様', 'nozawa.19008@kanagawa-pho.jp', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1),
  (gen_random_uuid(), 271, '今関信夫', '様', 'imaseki.hsc@chubuh.johas.go.jp', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1),
  (gen_random_uuid(), 271, '今枝智子', '様', 'renkei@chubuh.johas.go.jp', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 2),
  (gen_random_uuid(), 13, '柳館', '様', 'kurama.yanagidate@jmagrp.or.jp', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 3),
  (gen_random_uuid(), 165, '宗清', '様', 'munekiyo-masaaki@rakuwa.or.jp', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1),
  (gen_random_uuid(), 165, '倉田', '様', 'kurata-akito@rakuwa.or.jp', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 2),
  (gen_random_uuid(), 237, '林', '様', 'hayashimi@ekisai.or.jp', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1),
  (gen_random_uuid(), 237, '貝沼', '様', 'kainumaa@ekisai.or.jp', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 2),
  (gen_random_uuid(), 237, '近藤', '様', 'kondouda@ekisai.or.jp', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 3),
  (gen_random_uuid(), 273, '地域医療連携ご担当者', '様', 'itiiki@jimu.hokudai.ac.jp', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1),
  (gen_random_uuid(), 33, '金城', '様', 'a_kinjou@ns.omotokai.jp', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 2),
  (gen_random_uuid(), 24, '地域連携室ご担当者', '様', 'douai-chiikirenkei@outlook.jp', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1),
  (gen_random_uuid(), 137, '上野', '様', 'h.ueno@marianna-u.ac.jp', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1),
  (gen_random_uuid(), 23, '豊福', '様', 'toyofuku.r@jihs.go.jp', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 2),
  (gen_random_uuid(), 137, '滝澤', '様', 'shota.takizawa@marianna-u.ac.jp', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 2),
  (gen_random_uuid(), 137, '國重', '様', 'naoki.kunishige@marianna-u.ac.jp', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 3),
  (gen_random_uuid(), 482, '橋本', '様', 'hashimoto.tsutomu.tk@mail.hosp.go.jp', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1),
  (gen_random_uuid(), 137, '相澤', '様', 'r2aizawa@marianna-u.ac.jp', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 4),
  (gen_random_uuid(), 167, '和田', '様', 'm-renkei@teikyo-u.ac.jp', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 3),
  (gen_random_uuid(), 137, '保科', '様', 'tomofumi.hoshina@marianna-u.ac.jp', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 5),
  (gen_random_uuid(), 517, '岡部', '様', 'okabe@marianna-u.ac.jp', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1),
  (gen_random_uuid(), 121, '船井', '様', 'funai.kazuyuki@jp.panasonic.com', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 3),
  (gen_random_uuid(), 517, '田中', '様', 'awave@marianna-u.ac.jp', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 2),
  (gen_random_uuid(), 121, '渡辺', '様', 'watanabe.takumi001@jp.panasonic.com', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 4),
  (gen_random_uuid(), 517, '土屋', '様', 'satomi.tsuchiya@marianna-u.ac.jp', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 3),
  (gen_random_uuid(), 482, '上釜', '様', 'uekama.takuto.yq@mail.hosp.go.jp', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 2),
  (gen_random_uuid(), 157, '伊庭', '様', 'renkei@okayamasaiseikai.or.jp', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 3),
  (gen_random_uuid(), 482, '本村', '様', 'motomura.koki.wj@mail.hosp.go.jp', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 3),
  (gen_random_uuid(), 482, '甲斐', '様', 'kai.saori.su@mail.hosp.go.jp', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 4),
  (gen_random_uuid(), 482, '関', '様', 'seki.yukiko.ew@mail.hosp.go.jp', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 5),
  (gen_random_uuid(), 516, '澤田', '様', 'tsuyoshi_sawada@tmhp.jp', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1),
  (gen_random_uuid(), 516, '重田', '様', 'natsumi_shigeta@tmhp.jp', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 2),
  (gen_random_uuid(), 518, '木下', '様', 'kinoshita.akira@nihon-u.ac.jp', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1),
  (gen_random_uuid(), 518, '苅和野', '様', 'kariwano.youko@nihon-u.ac.jp', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 2),
  (gen_random_uuid(), 22, 'メダップ担当者', '様', 'shoya.shishido@medup.jp', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1),
  (gen_random_uuid(), 551, '上野', '様', 'ueno-hi@pref.gunma.lg.jp', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 1)
ON CONFLICT (tenant_id, email) DO NOTHING;

-- 問題なければ:
-- COMMIT;

-- 取り消すなら:
-- ROLLBACK;
