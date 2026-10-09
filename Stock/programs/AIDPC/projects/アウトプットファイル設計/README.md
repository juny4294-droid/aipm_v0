# アウトプットファイル設計

## 概要
コーディング結果をユーザーが扱いやすいように加工するエクセルファイル（VBA）を作成する

## 仕様
- [アウトプットファイル仕様](documents/3_planning/アウトプットファイル仕様.md)

## 作業中のブック
- [コーディング結果_取り込み.xlsm](development/code/コーディング結果_取り込み.xlsm)（生成スクリプト: [_build_import_workbook.py](development/code/_build_import_workbook.py)）
- 見本: [sample_コーディング結果_取り込み.xlsm](development/assets/sample_コーディング結果_取り込み.xlsm)
- 点数の検証結果: [点数検証_テスト用患者一覧_176件.csv](development/assets/点数検証_テスト用患者一覧_176件.csv)

## 入力・テストデータ（attachments/）
- 診断群分類電子点数表.xlsx（点数表マスタ。ブックの「点数表」シートの元）
- DPC6桁病名.xlsx（DPC上6桁と病名の対応表。ブックの「DPC6桁病名」シートの元）
- テスト用患者一覧_176件.xlsx / results_11_202606〜202607.csv（テスト用の患者一覧とAIコーディング結果）
- 対象患者リスト（退院日付き）.xlsx
- 20260902_済生会滋賀県病院_6-7月_精度チェック.xlsx / 20261005_済生会滋賀県病院_9月月次チェック.xlsx

## 開始日
2026-09-25

## 終了予定日
TBD

## 主要ステークホルダー
- TBD
