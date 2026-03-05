# API サンプル：1人目（上司・確認のみ）→ 2人目（自社押印）→ 3人目（相手押印）

以下の順でクラウドサインAPIを呼びます。事前にアクセストークンを取得し、各リクエストの `Authorization: Bearer <TOKEN>` に設定してください。

- **ベースURL（本番）**: `https://api.cloudsign.jp`
- **ベースURL（サンドボックス）**: `https://api-sandbox.cloudsign.jp`

---

## 前提

- `ACCESS_TOKEN` … 取得済みの Bearer トークン
- `contract.pdf` … 送る契約書PDF（パスは任意）
- 上司・自社・相手のメール・氏名は環境に合わせて書き換える

---

## Step 0. 書類を作成

```bash
curl -X POST "https://api-sandbox.cloudsign.jp/documents" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "title=業務委託契約書（APIテスト）" \
  -d "note=上司確認→自社押印→相手押印のテスト"
```

レスポンスJSONの **`id`** を `DOCUMENT_ID` として控える。

---

## Step 1. PDF を添付

```bash
curl -X POST "https://api-sandbox.cloudsign.jp/documents/${DOCUMENT_ID}/files" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -F "uploadfile=@./contract.pdf"
```

レスポンスの書類データ内 **`files[0].id`** を `FILE_ID` として控える。

---

## Step 2. 宛先を順番に3人追加（1: 上司 → 2: 自社 → 3: 相手）

**2-1. 1人目：上司（確認のみ・押印なし）**

```bash
curl -X POST "https://api-sandbox.cloudsign.jp/documents/${DOCUMENT_ID}/participants" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "name=上司 太郎" \
  -d "email=boss@yourcompany.co.jp"
```

**2-2. 2人目：自社（押印する）**

```bash
curl -X POST "https://api-sandbox.cloudsign.jp/documents/${DOCUMENT_ID}/participants" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "name=自社 花子" \
  -d "email=self@yourcompany.co.jp"
```

**2-3. 3人目：相手（押印する）**

```bash
curl -X POST "https://api-sandbox.cloudsign.jp/documents/${DOCUMENT_ID}/participants" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "name=取引先 一郎" \
  -d "email=partner@example.com"
```

3人追加後、書類の詳細を取得して **participants の `id`** を控える（2人目・3人目に押印を割り当てるため）。

```bash
curl -s -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  "https://api-sandbox.cloudsign.jp/documents/${DOCUMENT_ID}" | jq '.participants'
```

例:

- **order が 2 の宛先**（2人目＝自社）の `id` → `PARTICIPANT_ID_SELF`
- **order が 3 の宛先**（3人目＝相手）の `id` → `PARTICIPANT_ID_PARTNER`

※ 送信者は `order: 0`。追加した順に `order: 1`（上司）, `2`（自社）, `3`（相手）になる。`email` または `order` でどれが自社・相手か判定すること。

---

## Step 3. 押印を「2人目・3人目だけ」に割り当てる（1人目は割り当てない＝確認のみ）

入力項目の **type: 0 = 押印**。`page` は 0 始まり。`x`, `y` は PDF 上の座標（ポイント）。実際の位置に合わせて変更する。

**3-1. 2人目（自社）に押印を1つ追加**

```bash
curl -X POST "https://api-sandbox.cloudsign.jp/documents/${DOCUMENT_ID}/files/${FILE_ID}/widgets" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "participant_id=${PARTICIPANT_ID_SELF}" \
  -d "type=0" \
  -d "page=0" \
  -d "x=100" \
  -d "y=600"
```

**3-2. 3人目（相手）に押印を1つ追加**

```bash
curl -X POST "https://api-sandbox.cloudsign.jp/documents/${DOCUMENT_ID}/files/${FILE_ID}/widgets" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "participant_id=${PARTICIPANT_ID_PARTNER}" \
  -d "type=0" \
  -d "page=0" \
  -d "x=100" \
  -d "y=500"
```

**1人目（上司）には widget を追加しない** → 上司は「同意」ボタンのみで完了（確認者の扱い）。

---

## Step 4. 書類を送信

```bash
curl -X POST "https://api-sandbox.cloudsign.jp/documents/${DOCUMENT_ID}" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}"
```

これで、順番に「上司に確認依頼 → 上司が同意 → 自社に依頼 → 自社が押印して同意 → 相手に依頼 → 相手が押印して同意」と進み、締結完了する。

---

## まとめ（変数と順序）

| 変数 | 取得元 |
|------|--------|
| `DOCUMENT_ID` | Step 0 のレスポンス `id` |
| `FILE_ID` | Step 1 のレスポンス `files[0].id` |
| `PARTICIPANT_ID_SELF` | Step 2 後 GET 書類の `participants` のうち「自社」の `id` |
| `PARTICIPANT_ID_PARTNER` | 同「相手」の `id` |

| 順番 | 宛先 | widget（押印） | 役割 |
|------|------|----------------|------|
| 1 | 上司 | なし | 確認のみ |
| 2 | 自社 | あり（participant_id に割り当て） | 押印者 |
| 3 | 相手 | あり（participant_id に割り当て） | 押印者 |

押印を複数箇所に置く場合は、同じ `participant_id` で `POST .../widgets` を複数回呼ぶ。座標（`page`, `x`, `y`）だけ変えればよい。
