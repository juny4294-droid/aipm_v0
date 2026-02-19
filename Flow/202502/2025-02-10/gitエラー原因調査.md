# Git エラー原因調査レポート

**調査日**: 2025年2月10日  
**リポジトリ**: aipm_v0 (origin: https://github.com/juny4294-droid/aipm_v0.git)

---

## 1. 発生している問題の整理

現在、次の **2つ** の要因が重なっています。

---

## 2. 認証エラー（push 時に発生）

### エラーメッセージ

```
fatal: could not read Username for 'https://github.com': Device not configured
```

（あわせて `failed to get: -50` が出る場合あり）

### 原因

- **HTTPS** で GitHub に接続しており、push 時に **ユーザー名/パスワード（またはトークン）** が必要。
- 「Device not configured」は、**対話式の入力ができない環境**（Cursor のターミナルやスクリプト内など）で Git がユーザー名を聞こうとして失敗したときによく出ます。
- macOS の **キーチェーン（-50）** のエラーが出ている場合は、保存済み認証の参照に失敗している可能性もあります。

### 対処法

| 方法 | 手順 |
|------|------|
| **1. ターミナルで push** | 通常の macOS ターミナル（iTerm 等）を開き、`cd` でリポジトリに移動してから `git push`。その場で認証を求められれば入力する。 |
| **2. 認証情報の再保存** | ターミナルで `git push` を実行し、ユーザー名には GitHub のユーザー名、パスワードには **Personal Access Token (PAT)** を入力。保存を選べば次回以降はキーチェーンから利用される。 |
| **3. SSH に切り替え** | SSH 鍵を GitHub に登録し、`git remote set-url origin git@github.com:juny4294-droid/aipm_v0.git` でリモートを SSH に変更。以降は push 時に HTTPS 認証が不要になる。 |
| **4. GitHub CLI** | `brew install gh` → `gh auth login` でログインすると、HTTPS でも認証が通りやすくなる。 |

---

## 3. ブランチの分岐（push が拒否される原因）

### 状態

```
Your branch and 'origin/main' have diverged,
and have 1 and 3 different commits each, respectively.
```

- **ローカル main**: リモートにないコミットが **1つ**  
  - `7dcd880 2026021902`
- **origin/main**: ローカルにないコミットが **3つ**  
  - `3c617da 2026020902`  
  - `7b25290 Merge branch 'main' of ...`  
  - `e68cf93 20260218`

＝ 同じ `31c9d05` の後で、ローカルとリモートが別の履歴になっている状態です。

### なぜこうなるか

- 別のマシンや別のクローンで `2026020902` や `20260218` をコミットして push した。
- そのあと、この環境で `2026021902` を 1 コミットだけして、まだ pull していない。

このまま `git push` しても、リモートの方が先に進んでいるため **「rejected」** になり、push できません（認証が通っても同じ）。

### 対処法

1. **リモートの変更を取り込んでから push する（推奨）**
   ```bash
   git pull origin main   # マージコミットが1つ増える
   # コンフリクトが出たら解消してから
   git push origin main
   ```
2. **履歴を一直線にしたい場合**
   ```bash
   git pull --rebase origin main
   # コンフリクトが出たら解消し、git rebase --continue
   git push origin main
   ```

どちらも、**先に pull（または pull --rebase）してから push** する必要があります。

---

## 4. まとめ

| 現象 | 主な原因 | やること |
|------|----------|----------|
| `could not read Username` / `Device not configured` | HTTPS 認証が、この環境で聞けない・キーチェーン参照失敗 | 通常ターミナルで push、PAT 入力、または SSH/gh 利用 |
| push が rejected になる | ローカルと origin/main が分岐している | 先に `git pull` または `git pull --rebase` してから `git push` |

**推奨手順（このリポジトリで push を通すまで）**

1. macOS の通常ターミナルを開く。
2. `cd /Users/YamadaJun/Desktop/git/aipm_v0`
3. `git pull origin main`（または `git pull --rebase origin main`）
4. コンフリクトがなければ `git push origin main`
5. 認証を求められたら、GitHub ユーザー名と **PAT** を入力し、キーチェーンに保存する。

これで「認証エラー」と「分岐による push 拒否」の両方を解消できます。
