# Redmine 月次ロールオーバー自動化計画

Redmine の月次運用（チケットの次月移行と旧バージョンのクローズ）を自動化するための設計書です。

## 1. 目的
毎月手動で行っている、前月のバージョンから今月のバージョンへのチケット移行作業、および前月バージョンのクローズ作業を自動化し、作業ミスを削減し効率化を図ります。

## 2. 自動化の対象プロセス
1.  **バージョンの特定**: `YYYY-MM` 形式のバージョン名（例: `2024-02` と `2024-03`）を現在の日付から算出します。
2.  **チケットの移行**: 前月のバージョンに割り当てられている未完了のチケットを、すべて今月のバージョンに付け替えます。
3.  **バージョンのクローズ**: 前月のバージョンのステータスを「終了 (Closed)」に変更します。
4.  **新バージョンの作成（オプション）**: 必要に応じて、再来月のバージョンを先行して作成します。

## 3. 技術スタック
- **言語**: Ruby 3.x
- **標準ライブラリ**: `optparse` (引数解析), `json`, `net/http`
- **外部ライブラリ**: （必要に応じて）`rest-client` 等

## 4. スクリプト構成案 (scripts/redmine_rollover.rb)

### 4.1. 接続設定の取得
以下の優先順位で設定を取得します。
1.  コマンドラインオプション (`--redmine-url`, `--redmine-api-key`)
2.  環境変数 (`REDMINE_URL`, `REDMINE_API_KEY`)

※ `.env` ファイルの自動読み込みは行いません。

### 4.2. 実装ロジック
- `Date.today` を基準に、先月（`YYYY-MM`）と今月（`YYYY-MM`）の文字列を生成します。
- Redmine API を使用して以下の操作を行います：
    1.  プロジェクト内の全バージョンを取得。
    2.  先月のバージョンIDと今月のバージョンIDを特定。
    3.  先月のバージョンに紐付いているチケット（Issue）の一覧を取得。
    4.  それらのチケットの `fixed_version_id` を今月のバージョンIDに更新。
    5.  先月のバージョンのステータスを `closed` に更新。

## 5. 実行方法
```bash
# 環境変数を使用する場合
export REDMINE_URL=https://redmine.example.com
export REDMINE_API_KEY=your_api_key
ruby scripts/redmine_rollover.rb

# 引数で直接指定する場合
ruby scripts/redmine_rollover.rb --redmine-url https://redmine.example.com --redmine-api-key your_api_key
```

## 6. 今後のステップ
1.  [ ] Ruby スクリプトのプロトタイプ作成
2.  [ ] テスト用プロジェクトでの動作確認
3.  [ ] GitHub Actions 等による定期実行（Cron）の設定
