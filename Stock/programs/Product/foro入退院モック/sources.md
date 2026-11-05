# 更新元

このキットが写している現行画面の場所。モックを作るときには読まない。キットを最新の画面に合わせるときに読む。

実装リポジトリのファイルは、ここから読み取るだけにする。編集しない。

## いつ時点か

| 項目 | 値 |
|---|---|
| リポジトリ | `MedUpInc/medup-core-service` |
| ブランチ | `develop` |
| コミット | `ca6e7cd8a59eed53f00d1ffb3ec6ec93e6274f51` |
| 日時 | 2026-09-17 15:08:05 +0900 |
| 内容 | Merge pull request #4803 `feat/acf-web-patient-form` |
| キットへ写した日 | 2026-10-14 |
| アプリ | `apps/acute-care-flow-web` |

ローカルの作業ブランチは使わない。`origin/develop` を見る。

画面は、フラグ `NEXT_PUBLIC_FEATURE_FLAG_TRANSFER_REQUESTS_REDESIGN` が有効なときに合わせている。定義は `apps/acute-care-flow-web/src/utils/featureFlag.ts`。フラグが無効の短いフォームは、このキットの現行ではない。

## キットのファイルと元

| キット | 元 |
|---|---|
| [current.html](current.html) の相談一覧 | `src/features/TransferRequests/Index.tsx`、`statusGroups.ts`、`const.ts`、`styles.css.ts` |
| 一覧の表、タブ、バッジ | `src/components/foundations/DataDisplay/Table/styles.css.ts`、`src/components/foundations/Navigations/Tabs/styles.css.ts`、`src/components/foundations/StatusBadge/styles.css.ts` |
| 相談フォーム | `src/features/TransferRequests/components/PatientForm/`、`CreatePatientFormModal/`、`EditPatientFormSidePeak/` |
| 選択肢の文言 | `packages/foro-acute-care-flow-options/src/options/` |
| [current.html](current.html) のダッシュボード | `src/features/Dashboard/` |
| 地色、フォント、文字サイズ | `styles/global.css.ts`、`styles/DesignToken/color.ts`、`styles/DesignToken/typography.css.ts`、`styles/vars.css.ts` |
| ヘッダーと左ナビ | `src/layouts/components/Header/`、`src/layouts/components/Navigation/` |
| [screens.md](screens.md) | 上の画面の動きを短くしたもの |

パスは、アプリのルート `apps/acute-care-flow-web/` からの相対パス。選択肢のパッケージだけリポジトリ直下。

画面の地は `#FBF8FF`（`SemanticColor.background.main`）。ヘッダーは背景を塗らないので、この色が透ける。左ナビと相談一覧の紙面は白。ダッシュボードは同じ地の上に白い角丸パネルがある。

## キットを更新するとき

1. `origin/develop` を取得し、上のコミットより進んでいるかを見る。
2. 進んでいたら、上の表のファイルを読み、[current.html](current.html) と [screens.md](screens.md) を合わせる。
3. このファイルのコミット、日時、内容、写した日を書き換える。
4. フラグが無効の画面で上書きしない。配っている現行は、フラグが有効な画面である。
