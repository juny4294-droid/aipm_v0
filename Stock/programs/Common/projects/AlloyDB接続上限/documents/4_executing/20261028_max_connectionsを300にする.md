# 20261028 max_connections を 300 にする

更新: 2026-10-28

本番 AlloyDB の接続上限を、2 vCPU の推奨上限以内に下げる。アプリの再起動や接続の張り直しはしない。

## 背景

2026-09-29 に Google から、プロジェクト `medup-foro` の AlloyDB が新しい `max_connections` の目安を超えている、という案内が来た。対応期限は 2027年1月末。2027年Q3末からのデフォルト変更は新規作成のインスタンスだけで、今のインスタンスは自分で下げる。

対象はクラスタ `medup-foro-alloydb-kms-prd`（`asia-northeast1`）。

| インスタンス | 種別 | サイズ | 変更前の max_connections |
| --- | --- | --- | --- |
| `medup-foro-prd` | プライマリ（ZONAL） | `n2-highmem-2`（2 vCPU / 16GB） | 未設定。実効値 1000 |
| `medup-foro-read-prd` | リードプール（1ノード） | 同じ | 未設定。実効値 1000 |

フラグ一覧に `max_connections` が無いのでデフォルト。数値は Monitoring の `Connections limit` が 1000 だったことで確認した。

[AlloyDB の上限](https://cloud.google.com/alloydb/quotas) では、2 vCPU / 16GB の新しいデフォルトは 100、推奨上限は 570。1000 は推奨上限を超えている。

2026-09-29 時点の直近約72日の日次最大接続数は、プライマリ 135（中央値 108）、リード 129（中央値 113）。100 まで下げると今のピークで接続拒否になる。推奨上限 570 以下で余裕を見て **300** にする。

## 手順

コンソールは [クラスタ一覧](https://console.cloud.google.com/alloydb/clusters?project=medup-foro)。`max_connections` はリードプール側の制限があるので、先にリードプールへ入れる。値はプライマリ以上にする。両方 300。

更新は再起動を伴うが、コンソールは低停止モードで適用する。画面の黄色い警告は SSL などセキュリティ設定の話で、このフラグ変更とは別。

| 順 | 対象 | 停止 | 反映まで |
| --- | --- | --- | --- |
| 1 | `medup-foro-read-prd` | なし | 約10分 |
| 2 | 反映後に `medup-foro-prd` | ほとんどの場合 1秒未満 | 約15分 |

各インスタンスで次を行う。

1. インスタンスの編集を開く
2. フラグの「データベース フラグを追加」で `max_connections` = `300`。追加した直後の欄には実効値の 1000 が入っているので、300 に書き換える
3. インスタンスを更新する
4. リードプールが反映してからプライマリを更新する

リードプールをプライマリの実効値より小さくすると拒否される。先にリードを 1000 のまま保存してしまった場合は、プライマリを 300 にしてからリードを 300 に下げる。

プライマリの更新直前に、実行中のインポートが無いことを見る。Query Insights か実行中クエリで、`COPY` や長時間の `INSERT` が無ければ更新する。当たった場合、そのインポート1件が失敗し、未コミット分はロールバックされる。ユーザーが同じ投入をやり直せば完了する。サービス全体は止まらない。アプリの再起動や接続の張り直しは不要。

## 時刻

2026-09-29 までの直近21日で、プライマリの1時間あたり挿入行数は次のとおり。

| 時刻（JST） | 中央値 | 最大 |
| --- | --- | --- |
| 22時台 | 4 | 176 |
| 23時台 | 314 | 558 |
| 0時台 | 6 | 63 |
| 1時台 | 169万 | 182万 |
| 2時台 | 158万 | 353万 |

23時に始める。反映の約15分は 0時台に収まり、1時からの一括挿入には重ならない。1時以降は避ける。

## 今回

実施者: 山田潤（`jun.yamada@medup.jp`）。2026-10-28 の 21時台に実施し、1時の一括挿入の前に終えた。

| 時刻（JST） | 内容 |
| --- | --- |
| 21:03 | リードプールにフラグを追加して更新。欄の初期値 1000 のまま保存された |
| 21:15 | リードプールの更新完了。`max_connections` = `1000` |
| 21:18 | プライマリを `300` で更新開始 |
| 21:27 | 新しいサーバーの起動直後に、AlloyDB 内部の管理接続が FATAL を出した。利用者のトランザクションではない |
| 21:30:18 | `foro_prd` の `foro_command_user` で接続リセットが 1 件。切り替わりに重なった利用者側の切断 |
| 21:30:22 | プライマリが読み書きを受け付け開始 |
| 21:35 | プライマリの反映完了。`max_connections` = `300`。`Connections limit` も 300 |
| 21:36 | リードプールを `300` で更新開始 |
| 21:48 | リードプールの反映完了。`max_connections` = `300` |

完了時点で両方とも `READY`、`reconciling` は false。アプリの再起動や接続の張り直しはしていない。

21:20:45 に `data_ops_prd` の `postgres` で接続リセットが 1 件ある。起動より前なので、この更新で切った接続ではない。

利用者側の切断を探すクエリ:

```
resource.type="alloydb.googleapis.com/Instance"
resource.labels.instance_id="medup-foro-prd"
log_id("alloydb.googleapis.com/postgres.log")
timestamp>="2026-10-28T21:18:00+09:00"
timestamp<="2026-10-28T21:40:00+09:00"
textPayload:"client backend"
NOT textPayload:"user=alloydbadmin"
(
  textPayload:"Connection reset"
  OR textPayload:"could not receive data from client"
  OR textPayload:"unexpected EOF"
  OR textPayload:"terminating connection due to administrator command"
)
```
