## 実装前提（2026-08-26 更新）
- **対象期間**: 直近1年。今回は `2025-08-01` 〜 `2026-07-31`（年度区切りではない）
- **親集合**: `patient_summary_by_department` は**使わない**。`medup-foro.dpc_patient_records_prd.outpatient_ef` を `outpatient_date` で期間絞り、医師マスタの担当診療科で看る
- **最大行為・受診回数・併科**: 年度サマリーではなく、同じ期間の EF から再集計
- 詳細の条件表: [20260807_抽出条件確認用_3診療科（病院確認）](https://app.notion.com/p/3b51da5a7f3b8191b014e46afe9ba2a4)
概要
鳥取県栗中央病院の逆紹介リスト作成
３診療科（整形外科、脳神経外科、泌尿器科）からヒアリングした条件をもとに抽出のためのクエリを作成する
<empty-block/>
まずはヒアリングした条件を精査し、クエリ条件への変換を行う
- 整形外科（村田先生・山下先生・皆川様）
	- 対象：**併科含む**。最大行為が処置/手術/注射以下（点数の線引きなし・受診回数でも一律除外しない）。
		- 骨粗鬆症注射（プラリア年2回＋内服＋骨密度年1回）は回数が多くても対象
	- 対象外：**CT・MRI**（定期フォロー用途が少ないため）／**ギプス・脱臼**（非観血的骨折整復術等・救急経由）／逆紹介済み（自診療科から該当期間内に逆紹介が入っていること）
	- 個別論点
		- 難病・特定疾患の書類対応患者（6月に集中）→受け皿の書類作成可否をアンケートで確認
		- 抗生剤長期投薬はほぼいないため考慮せず。人工関節フォローは施設差があり一律ルールなし
	- 方針：広めに抽出→先生のフィードバックでチューニング。「すでに逆紹介済みの患者もいるはず」→ゾーン別の逆紹介実績を確認したい（山下先生）
	<details>
	<summary>思考の流れ</summary>
		- 親となる集合→`medup-foro.dpc_patient_records_prd.outpatient_ef`（直近1年で期間絞り。`patient_summary_by_department` は使わない）
			- **併科含む**。最大行為が処置/手術/注射以下
				- 対象診療科に整形外科がある
					- 鳥取の場合は、「医師マスタ上の担当診療科が整形外科の医師」が担当した診療
				- 最大行為がxx
			- データの期間：2025/8/1〜2026/7/31（直近1年）
				- ここは可変らしい
			- 除外する集合
				- **CT・MRI**（定期フォロー用途が少ないため）
					- 元となるデータ→`medup-foro.dpc_patient_records_prd.outpatient_ef`
						- 大元のデータソース→外来EF
					- 定義
						- 期間：2025/4\~2026/3
						<details>
						<summary>CT・MRI：レセプトコードが次に該当するもの</summary>
							```yaml
- "170011710"
- "170011810"
- "170012070"
- "170015210"
- "170020110"
- "170020470"
- "170027310"
- "170028610"
- "170033410"
- "170033510"
- "170034910"
- "170035010"
- "170038810"
- "170038910"
- "170040210"
- "170040250"
- "170040410"
- "170040610"
- "170041410"
- "170041610"
- "170704810"
- "170704910"
- "170901710"
							```
							<details>
							<summary>CT</summary>
								```yaml
'170011710', 
'170011810', 
'170012070', '170015210', '170020110',
              '170020470', '170027310', '170028610', '170033410', '170033510',
              '170034910', '170035010', '170038810', '170038910', '170040210',
              '170040250', '170040410', '170040610', '170041410', '170041610',
              '170704810', '170704910', '170901710'
								```
							</details>
							<details>
							<summary>MRI</summary>
								```yaml
あとで
								```
							</details>
						</details>
						- イメージは指定期間内にCT/MRIのレセプトコードの算定があったpatient_id一覧を抽出する
				- **ギプス・脱臼**（非観血的骨折整復術等）
					- 元となるデータ→`medup-foro.dpc_patient_records_prd.outpatient_ef`
						- 大元のデータソース→外来EF
					- 期間：2025/4\~2026/3
					- ギプス・脱臼
						- 確認事項：どちらの請求コードを対象に除外するか？→CSに確認してもらう
							- ギプス→2025年度は310件
								- 付けて外すと考えればほぼどっちでも同じ
							- 非観血的整復術→2025年度は140件
								- 脱臼と骨折含む
				- 逆紹介済み（自診療科から該当期間内に逆紹介が入っていること）
					- 元となるデータ→`medup-foro.foro_prd.public_reverse_referrals`
						- 大元のデータソース→逆紹介データ
							- foro CRMで使っているものの流用
				参考
				![](https://prod-files-secure.s3.us-west-2.amazonaws.com/4b4dc718-e981-4c88-a830-7289370c468a/848fdcab-cc30-4c35-8b5d-e4c472bb6234/image.png?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Content-Sha256=UNSIGNED-PAYLOAD&X-Amz-Credential=ASIAZI2LB4663O37B7PM%2F20260826%2Fus-west-2%2Fs3%2Faws4_request&X-Amz-Date=20260826T132703Z&X-Amz-Expires=300&X-Amz-Security-Token=IQoJb3JpZ2luX2VjEFQaCXVzLXdlc3QtMiJGMEQCIEf2nFDQm6QK0ouAwEN7zIFE9idWbcQr%2BlAZv1%2FHfyzoAiBq3f43wjx6na%2FHADh42BKLB5%2BDpcvgVAJ6uRG9DgzbNir%2FAwgdEAAaDDYzNzQyMzE4MzgwNSIMzeyXs0PVEL99FQyqKtwDeUaj4v%2F3i%2FIZjpt0LHWptlNHOFxoBOJnIS%2BywT8vRMvq0lS72RZ4nueg4QwXaf9fmfe3z88Dtb2%2BWM36WYGPbjGBd1uiXiwjRi1TS7c2ZT6hD53%2F446KXsns4q1Q1Uc5R4Q9wyAHlg16u5N7PuBK9gBqohgrJ1lb3wYMFJrGkOBFZdb27HFtlm4XqZMlTv4lL3viG90p8V5lIyAD%2B1vc3lEdr0umVmCR%2FgTlwqf7UnRIYhf%2BqqP8oszybGfPy8AdSWE%2FzVgGe4kj1XiQf0lH1fX%2F1VEWLd7lLikYBMCvcOvhHHCNanD3IWWPbwdDCB3NQLQguMBtWop54kSiGObNtuz%2BErmSWq%2Fk%2Fg4E2p4bHKjUmE3WaOsk3IM1LFuHfoXhLdJSK3QlFycF1XbgUP9MIyPCe%2FCr8T14LZtDX%2FmK0j4zW4ptNN7jloQ6fiBB4Bnbjmm34QJ9c9fE%2FuB5XjKA4hp5Vv31BzKSJQn5EsEozgJ04FwCz%2F%2BH8NQbYi2QnwgkvNjrhSakO0q9mbF02i9vSIq5DHKj1ZsgB7e0XaTE0Dp7XobD%2FibrJJuYZ8Q6mmWBH7hL6QiTfZ8xVj78sJfP5j5GZ4rCgn7rP9p%2BYbj7apcICL4HAKyIFOB5wQAw56e71AY6pgGBPq53dAisacuLXKUzWh9JcnXlUuh3zD3X8rON9a1mbzB1gr98lleuX07%2B9Bw8T8bXMC4DY6cJ8a9XXUGmR6HFMQ%2FLiZFEW55HhhGdpHtxX50RfC%2B4PQfCsLvZJKkL0YLpWt5WrivhxQBjTEQuw%2BKyzxpIg%2B1YESZiAcgWY7HQQNqgvl04jN9rORrPU3PwwGgv8EuqhTldhLjypoSjzFGd2Ih0lbMG&X-Amz-Signature=96400bac6b38620645d1416e8bb8c5194884a54bf1f25e4e34ad1f87bd6adda6&X-Amz-SignedHeaders=host&x-amz-checksum-mode=ENABLED&x-id=GetObject)
	</details>
- 脳神経外科
	- 対象：**単純MRIフォロー患者**
		- ~~（良性腫瘍で安定・頭部外傷・脳卒中後・くも膜下出血術後6年以上）~~。
		- 1.5テスラのMRI算定患者
		- 3.0テスラのMRI算定患者
	<empty-block/>
	- 対象外：
		- 併科→できる
		- CT→CTの算定ありを対象外に出来る
		- 悪性腫瘍→DPCコードどれ？AND  直近6年以内に手術していないことはわかるが、病名の特定は不可能
			- 悪性腫瘍管理料？
			- 入院手術？から病名とる
				- **010010 脳腫瘍**
					<details>
					<summary><span color="red">**010010「脳腫瘍」**</span><span color="red">（MDC01 神経系疾患）の1つに悪性・良性・性状不詳がすべて含まれる。そのため、悪性腫瘍特異物質治療管理料の算定がある患者を除く形が良いと思ったが不十分</span></summary>
						※悪性脳腫瘍は血清腫瘍マーカーがなく「悪性腫瘍特異物質治療管理料」は算定されにくい → 薬剤・化学療法・がん系管理料で判定が良さそうなため、その方向で進めたい。
						[https://docs.google.com/spreadsheets/d/1oyN9e33eOZ2DbbYjh9vuWBDqBlU5Mpz4/edit?gid=1450326094#gid=1450326094](https://docs.google.com/spreadsheets/d/1oyN9e33eOZ2DbbYjh9vuWBDqBlU5Mpz4/edit?gid=1450326094#gid=1450326094)
						![](https://prod-files-secure.s3.us-west-2.amazonaws.com/4b4dc718-e981-4c88-a830-7289370c468a/0c4ffad2-ddaa-496d-869e-de35bb5d37a7/image.png?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Content-Sha256=UNSIGNED-PAYLOAD&X-Amz-Credential=ASIAZI2LB4663O37B7PM%2F20260826%2Fus-west-2%2Fs3%2Faws4_request&X-Amz-Date=20260826T132703Z&X-Amz-Expires=300&X-Amz-Security-Token=IQoJb3JpZ2luX2VjEFQaCXVzLXdlc3QtMiJGMEQCIEf2nFDQm6QK0ouAwEN7zIFE9idWbcQr%2BlAZv1%2FHfyzoAiBq3f43wjx6na%2FHADh42BKLB5%2BDpcvgVAJ6uRG9DgzbNir%2FAwgdEAAaDDYzNzQyMzE4MzgwNSIMzeyXs0PVEL99FQyqKtwDeUaj4v%2F3i%2FIZjpt0LHWptlNHOFxoBOJnIS%2BywT8vRMvq0lS72RZ4nueg4QwXaf9fmfe3z88Dtb2%2BWM36WYGPbjGBd1uiXiwjRi1TS7c2ZT6hD53%2F446KXsns4q1Q1Uc5R4Q9wyAHlg16u5N7PuBK9gBqohgrJ1lb3wYMFJrGkOBFZdb27HFtlm4XqZMlTv4lL3viG90p8V5lIyAD%2B1vc3lEdr0umVmCR%2FgTlwqf7UnRIYhf%2BqqP8oszybGfPy8AdSWE%2FzVgGe4kj1XiQf0lH1fX%2F1VEWLd7lLikYBMCvcOvhHHCNanD3IWWPbwdDCB3NQLQguMBtWop54kSiGObNtuz%2BErmSWq%2Fk%2Fg4E2p4bHKjUmE3WaOsk3IM1LFuHfoXhLdJSK3QlFycF1XbgUP9MIyPCe%2FCr8T14LZtDX%2FmK0j4zW4ptNN7jloQ6fiBB4Bnbjmm34QJ9c9fE%2FuB5XjKA4hp5Vv31BzKSJQn5EsEozgJ04FwCz%2F%2BH8NQbYi2QnwgkvNjrhSakO0q9mbF02i9vSIq5DHKj1ZsgB7e0XaTE0Dp7XobD%2FibrJJuYZ8Q6mmWBH7hL6QiTfZ8xVj78sJfP5j5GZ4rCgn7rP9p%2BYbj7apcICL4HAKyIFOB5wQAw56e71AY6pgGBPq53dAisacuLXKUzWh9JcnXlUuh3zD3X8rON9a1mbzB1gr98lleuX07%2B9Bw8T8bXMC4DY6cJ8a9XXUGmR6HFMQ%2FLiZFEW55HhhGdpHtxX50RfC%2B4PQfCsLvZJKkL0YLpWt5WrivhxQBjTEQuw%2BKyzxpIg%2B1YESZiAcgWY7HQQNqgvl04jN9rORrPU3PwwGgv8EuqhTldhLjypoSjzFGd2Ih0lbMG&X-Amz-Signature=08d940f88e6d9b64c7b89afb4879f29a32b252648ad2eda863537a38f695b5f5&X-Amz-SignedHeaders=host&x-amz-checksum-mode=ENABLED&x-id=GetObject)
						![](https://prod-files-secure.s3.us-west-2.amazonaws.com/4b4dc718-e981-4c88-a830-7289370c468a/419dcf33-2760-4dd2-a2e6-1bed5ef37ba7/image.png?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Content-Sha256=UNSIGNED-PAYLOAD&X-Amz-Credential=ASIAZI2LB4663O37B7PM%2F20260826%2Fus-west-2%2Fs3%2Faws4_request&X-Amz-Date=20260826T132703Z&X-Amz-Expires=300&X-Amz-Security-Token=IQoJb3JpZ2luX2VjEFQaCXVzLXdlc3QtMiJGMEQCIEf2nFDQm6QK0ouAwEN7zIFE9idWbcQr%2BlAZv1%2FHfyzoAiBq3f43wjx6na%2FHADh42BKLB5%2BDpcvgVAJ6uRG9DgzbNir%2FAwgdEAAaDDYzNzQyMzE4MzgwNSIMzeyXs0PVEL99FQyqKtwDeUaj4v%2F3i%2FIZjpt0LHWptlNHOFxoBOJnIS%2BywT8vRMvq0lS72RZ4nueg4QwXaf9fmfe3z88Dtb2%2BWM36WYGPbjGBd1uiXiwjRi1TS7c2ZT6hD53%2F446KXsns4q1Q1Uc5R4Q9wyAHlg16u5N7PuBK9gBqohgrJ1lb3wYMFJrGkOBFZdb27HFtlm4XqZMlTv4lL3viG90p8V5lIyAD%2B1vc3lEdr0umVmCR%2FgTlwqf7UnRIYhf%2BqqP8oszybGfPy8AdSWE%2FzVgGe4kj1XiQf0lH1fX%2F1VEWLd7lLikYBMCvcOvhHHCNanD3IWWPbwdDCB3NQLQguMBtWop54kSiGObNtuz%2BErmSWq%2Fk%2Fg4E2p4bHKjUmE3WaOsk3IM1LFuHfoXhLdJSK3QlFycF1XbgUP9MIyPCe%2FCr8T14LZtDX%2FmK0j4zW4ptNN7jloQ6fiBB4Bnbjmm34QJ9c9fE%2FuB5XjKA4hp5Vv31BzKSJQn5EsEozgJ04FwCz%2F%2BH8NQbYi2QnwgkvNjrhSakO0q9mbF02i9vSIq5DHKj1ZsgB7e0XaTE0Dp7XobD%2FibrJJuYZ8Q6mmWBH7hL6QiTfZ8xVj78sJfP5j5GZ4rCgn7rP9p%2BYbj7apcICL4HAKyIFOB5wQAw56e71AY6pgGBPq53dAisacuLXKUzWh9JcnXlUuh3zD3X8rON9a1mbzB1gr98lleuX07%2B9Bw8T8bXMC4DY6cJ8a9XXUGmR6HFMQ%2FLiZFEW55HhhGdpHtxX50RfC%2B4PQfCsLvZJKkL0YLpWt5WrivhxQBjTEQuw%2BKyzxpIg%2B1YESZiAcgWY7HQQNqgvl04jN9rORrPU3PwwGgv8EuqhTldhLjypoSjzFGd2Ih0lbMG&X-Amz-Signature=6e4cc66959f396ae9574ed88fbaea305d24e678963d58e6a4e91914c61c28dcc&X-Amz-SignedHeaders=host&x-amz-checksum-mode=ENABLED&x-id=GetObject)
					</details>
		- 血管内手術後（ステント・コイル→血小板凝集能検査で識別）→手技指定してほしいです AND 直近6年以内に手術していないことはわかるが、病名の特定は不可能
			<details>
			<summary><span color="red">Kコードだけだと過去分が拾えないので、以下を見て欲しいです</span></summary>
				# 【依頼】脳神経外科・除外条件「血管内手術後」の実データ確認
				**依頼先**：データチーム（黒川さん・山田さん）<br>**背景**：脳神経外科の逆紹介候補から「血管内手術後（ステント・コイル）」の患者を除外したい。判定方式を **(a) 手術Kコード** と **(b) 血小板凝集能検査の算定** の2系統で検証して確定する。<br>**前提**：逆紹介の主目的はMRI検査枠の逼迫解消のため、**除外は安全側（広め）でよい**（外来枠を無理に空ける必要はない）。
				## なぜ単品では足りないか
				- **(a) Kコードだけでは足りない**：入院データの遡及可能範囲より前（2019年以前想定）の手術が捕捉できない。コイル・ステント後の画像フォローは5〜10年続くのが一般的で、2025年度の外来フォロー患者には遡及範囲外の手術例が相当数含まれる見込み。
				- **(b) 血小板凝集能だけでは足りない**：術後フォローで必ず算定されるかは施設の運用次第（ルーチン測定でなければ漏れる）。また血管内手術をしていない抗血小板薬患者にも算定されうるが、こちらは安全側除外の方針のため許容できる。**主なリスクは「漏れ」側**。
				## 今回の検証の目的
				2系統の弱点を互いに補えるかを実データで確認すること。具体的には、**(a)該当者に対する(b)の算定率**を見て「血管内手術後には血小板凝集能がルーチン算定されている」と言えるかを確認する。言えれば、**遡及できない過去の手術患者も(b)で補完できる**と判断でき、(a)∪(b)のOR条件で「漏れなし」を確定できる。
				## 確認してほしいこと（対象：脳神経外科・2025年度外来の逆紹介検討対象患者）
				1. **(a) Kコード該当者の抽出**：下記Kコードの手術歴がある患者（入院データ・遡れる範囲すべて）→ 該当人数
				2. **(b) 血小板凝集能の算定者の抽出**：下記コードが期間内に1回でも算定されている患者 → 該当人数
				3. **(a)×(b) の突合**：
					- (a)該当者のうち(b)の算定もある人数 → ルーチン算定かどうかの確認（検証の本丸）
					- (b)のみ該当（Kコードなし）の人数
				4. **入院データの遡及可能期間**：何年の手術まで遡れるか（2019年以前は遡れない想定で合っているか）
				## 確定ルール（案）
				- 原則 **(a) ∪ (b) のOR条件で除外**（Kコードで確実に拾い、遡及できない過去の手術を血小板凝集能で補完）
				- (a)該当者への(b)算定率が低い場合＝ルーチン算定でない場合は、遡及範囲外の補完が効かないため、Kコードのみ＋先生によるリスト確認に切り替えて相談
				- (b)のみ該当が想定外に多い場合のみ、中身を数例確認のうえ相談
				![](https://prod-files-secure.s3.us-west-2.amazonaws.com/4b4dc718-e981-4c88-a830-7289370c468a/f94496b1-47b9-419d-a40b-7a02eb2d67b9/image.png?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Content-Sha256=UNSIGNED-PAYLOAD&X-Amz-Credential=ASIAZI2LB4663O37B7PM%2F20260826%2Fus-west-2%2Fs3%2Faws4_request&X-Amz-Date=20260826T132703Z&X-Amz-Expires=300&X-Amz-Security-Token=IQoJb3JpZ2luX2VjEFQaCXVzLXdlc3QtMiJGMEQCIEf2nFDQm6QK0ouAwEN7zIFE9idWbcQr%2BlAZv1%2FHfyzoAiBq3f43wjx6na%2FHADh42BKLB5%2BDpcvgVAJ6uRG9DgzbNir%2FAwgdEAAaDDYzNzQyMzE4MzgwNSIMzeyXs0PVEL99FQyqKtwDeUaj4v%2F3i%2FIZjpt0LHWptlNHOFxoBOJnIS%2BywT8vRMvq0lS72RZ4nueg4QwXaf9fmfe3z88Dtb2%2BWM36WYGPbjGBd1uiXiwjRi1TS7c2ZT6hD53%2F446KXsns4q1Q1Uc5R4Q9wyAHlg16u5N7PuBK9gBqohgrJ1lb3wYMFJrGkOBFZdb27HFtlm4XqZMlTv4lL3viG90p8V5lIyAD%2B1vc3lEdr0umVmCR%2FgTlwqf7UnRIYhf%2BqqP8oszybGfPy8AdSWE%2FzVgGe4kj1XiQf0lH1fX%2F1VEWLd7lLikYBMCvcOvhHHCNanD3IWWPbwdDCB3NQLQguMBtWop54kSiGObNtuz%2BErmSWq%2Fk%2Fg4E2p4bHKjUmE3WaOsk3IM1LFuHfoXhLdJSK3QlFycF1XbgUP9MIyPCe%2FCr8T14LZtDX%2FmK0j4zW4ptNN7jloQ6fiBB4Bnbjmm34QJ9c9fE%2FuB5XjKA4hp5Vv31BzKSJQn5EsEozgJ04FwCz%2F%2BH8NQbYi2QnwgkvNjrhSakO0q9mbF02i9vSIq5DHKj1ZsgB7e0XaTE0Dp7XobD%2FibrJJuYZ8Q6mmWBH7hL6QiTfZ8xVj78sJfP5j5GZ4rCgn7rP9p%2BYbj7apcICL4HAKyIFOB5wQAw56e71AY6pgGBPq53dAisacuLXKUzWh9JcnXlUuh3zD3X8rON9a1mbzB1gr98lleuX07%2B9Bw8T8bXMC4DY6cJ8a9XXUGmR6HFMQ%2FLiZFEW55HhhGdpHtxX50RfC%2B4PQfCsLvZJKkL0YLpWt5WrivhxQBjTEQuw%2BKyzxpIg%2B1YESZiAcgWY7HQQNqgvl04jN9rORrPU3PwwGgv8EuqhTldhLjypoSjzFGd2Ih0lbMG&X-Amz-Signature=59e578da748f9e4007d629b91a8340a8a157728e58d04a0018d6c22305980767&X-Amz-SignedHeaders=host&x-amz-checksum-mode=ENABLED&x-id=GetObject)
				## 使用コード
				### (a) 手術Kコード（レセ電算コード）
				<table header-row="true">
<tr>
<td>区分</td>
<td>名称</td>
<td>レセ電算コード</td>
</tr>
<tr>
<td>K178</td>
<td>脳血管内手術（1箇所）</td>
<td>150254910</td>
</tr>
<tr>
<td>K178</td>
<td>脳血管内手術（2箇所以上）</td>
<td>150344410</td>
</tr>
<tr>
<td>K178</td>
<td>脳血管内手術（脳血管内ステント）</td>
<td>150355410</td>
</tr>
<tr>
<td>K178-2</td>
<td>経皮的脳血管形成術</td>
<td>150273510</td>
</tr>
<tr>
<td>K178-5</td>
<td>経皮的脳血管ステント留置術</td>
<td>150380850</td>
</tr>
<tr>
<td>K609-2</td>
<td>経皮的頸動脈ステント留置術</td>
<td>150337110</td>
</tr>
<tr>
<td>K609-2</td>
<td>経皮的頸動脈ステント留置術（薬事承認又は認証医療機器）</td>
<td>150453450</td>
</tr>
<tr>
<td>K178-4</td>
<td>経皮的脳血栓回収術 ※</td>
<td>150372510</td>
</tr>
<tr>
<td>K178-3</td>
<td>経皮的選択的脳血栓・塞栓溶解術（頭蓋内脳血管） ※</td>
<td>150301110</td>
</tr>
<tr>
<td>K178-3</td>
<td>経皮的選択的脳血栓・塞栓溶解術（頸部脳血管）（内頸、椎骨動脈） ※</td>
<td>150301210</td>
</tr>
				</table>
				※印3件は急性期の血栓回収・溶解（ステント・コイルとは異なる血管内治療）。除外は安全側でよいため**含める案**。
				### (b) 血小板凝集能（D006）
				<table header-row="true">
<tr>
<td>名称</td>
<td>レセ電算コード</td>
</tr>
<tr>
<td>血小板凝集能（その他）</td>
<td>160238710</td>
</tr>
<tr>
<td>血小板凝集能（鑑別診断の補助に用いるもの）</td>
<td>160238610</td>
</tr>
				</table>
				**コード出典**：厚生労働省 診療報酬情報提供サービス「診療報酬マスター（令和6年度版）」診療行為マスタ s_20260501.csv<br>[https://shinryohoshu.mhlw.go.jp/shinryohoshu/downloadMenu/](https://shinryohoshu.mhlw.go.jp/shinryohoshu/downloadMenu/)
			</details>
		- 造影MRI継続（生化学的検査・BUN併算定が代理指標）
			- →MRI+造影剤使用加算なら判別できる。
			- 継続って何？→直近MRIが造影（造影剤加算が乗っている）
				- ~~直近xxヶ月以内に算定がある？~~
		- てんかん→慢性疾患だからてんかんの入院歴が直近のデータ内にある人しかわからない
			- てんかん指導料の算定でOK
		- くも膜下出血 術後6年未満
			- DPCやICD10だとなに？
				- 010020 くも膜下出血、破裂脳動脈瘤
		- 逆紹介済み（自診療科から該当期間内に逆紹介が入っていること）→できる
- 泌尿器科
	- 対象：
		- **CT年2回以下**／**検査年5回以下**（メインは年1〜2回のPSA）／投薬・再診のみ
			- それぞれの条件は出来るが、ANDなの？ORなの？
	- 対象外：
		- 併科→できる
		- MRI実施（≒前立腺がん）→できる（病名の特定までは微妙）
		- 鳥取大学からの紹介患者（ロボット手術後フォロー）→できる（ロボット手術後フォロー化の特定はできない）
		- 前立腺がん術後5年未満（6年目以降は可）→できる（データが7年分くらいあるから）
<empty-block/>
<empty-block/>
<mention-page url="https://app.notion.com/p/3b01da5a7f3b8035b72ddc9572603845"/> 
<empty-block/>
- 積極的監視療法中（前立腺がんで入院有り、手術無しの患者で、定期検査をしている患者）
	- 前立腺がんで入院有り/手術無しの患者
		- **110080 前立腺の悪性腫瘍**
		- 2019/4以降のものであればできる
	- 定期検査をしている
		- 指定期間内にxx回？
		- 検査はなんでもいい？
	<details>
	<summary><span color="red">判定ロジック（吉田）</span></summary>
		**【泌尿器科・逆紹介候補抽出】除外条件⑦「積極的監視療法中」の判定ロジック（確定版）**
		**背景**
		7/30泌尿器科面談（村岡先生）で「積極的監視療法中の患者は逆紹介不可」と確定。積極的監視療法＝悪性腫瘍（主に前立腺がん）で手術をせず監視するプロトコルで、がん診断後2年以内にMRI、5年以内に生検、PSA採血を年2〜4回実施する。同面談で「PSA採血が年1〜2回のみの安定フォロー患者は逆紹介可能」も確定しているため、未手術のがん患者を一律除外にはせず、3ステップで判定する。
		**判定ロジック**
		- **Step1｜がんフォロー患者の網掛け**抽出対象期間（直近1年）に泌尿器科で悪性腫瘍特異物質治療管理料の算定がある患者を抽出（補助指標：骨シンチグラフィ・前立腺針生検の算定歴＝全期間遡り）。非該当はここで判定終了（通常の候補判定へ）※「現在がんフォロー中か」の判定なので管理料は直近1年で見る。補助指標のみ過去に遡る
		- **Step2｜治療歴での分岐**（算定歴はデータ基盤の全期間＝2019年4月〜を遡る）
			- 泌尿器科の悪性腫瘍手術の算定歴あり → 既存の条件⑥（術後5年未満は除外）へ
			- 手術歴なし（未治療） → Step3へ
		- **Step3｜積極的監視療法の判定**
			- (a) 直近3年以内に前立腺生検またはMRIの算定あり → **除外**（積極的監視療法疑い）
			- (b) (a)非該当 かつ 管理料の初回算定が直近1〜2年以内 → **リストに残す** ※フォロー開始が浅い層。「がんフォロー（開始2年以内）」フラグを付けて医師が判別できるようにする
			- (c) それ以外（未治療・生検/MRIから遠い・PSA年1〜2回程度） → **候補に残す**（本筋の返す患者。「がんフォロー」フラグ付き）
		**整合性の確認（見直しで確認済みの点）**
		- 既存条件②（MRI実施＝除外）は直近1年が対象なので、Step3(a)の実効範囲は「1〜3年前に生検/MRIがあった患者」。重複はあるが矛盾しない
		- データ基盤開始（2019年4月）以前の手術は捕捉できないが、その場合は術後6年以上経過しており「術後5年経過後は逆紹介可能」と整合するため実害なし
		- 判定根拠（管理料の初回算定年月・手術算定日・直近の生検/MRI算定日）をリストの列として持たせると、医師確認と後々の条件チューニングが楽になる
		**要確定・要確認**
		- 算定コード：悪性腫瘍特異物質治療管理料／前立腺針生検／前立腺MRI／骨シンチグラフィ／悪性腫瘍手術（ロボット支援含む）
		- 閾値「直近3年」「初回算定1〜2年」は仮置き → 生検間隔の院内運用を次回面談で確認して調整
		- 検証：Step1該当者数と現行対象ゾーン（検査 年5回以下／CT 年2回以内／投薬・再診）の重なり件数を先に出して規模感を確認したい
		**既知の限界（仕様として許容）**
		- 他院で診断され監視のみ当院で行う患者は院内に生検/MRI算定がなく(a)で捕捉不可 → (b)(c)のフラグで医師確認に乗る設計（無印で候補リストに素通りはしない）
		- 腎腫瘍の監視患者は腫瘍マーカーがなく管理料の網にかからない → レセプト病名（C64等）が使えるか要確認。件数は少ない見込み（医師談）
		- 放射線治療後の患者は手術歴がないためStep3に流れ、多くは(c)で候補に残る → 「放射線治療後も術後5年ルールに準じるか」を次回面談の確認事項に追加
	</details>
	逆紹介済み（自診療科から該当期間内に逆紹介が入っていること）
<empty-block/>
<empty-block/>
<page url="https://app.notion.com/p/3b51da5a7f3b8191b014e46afe9ba2a4">20260807_抽出条件確認用_3診療科（病院確認）</page>
