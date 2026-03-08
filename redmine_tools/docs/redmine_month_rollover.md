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
- **標準ライブラリのみ使用**:
    - `optparse`: コマンドライン引数の解析
    - `net/http`, `uri`, `openssl`: Redmine REST API との通信
    - `json`: API レスポンスのパースおよびリクエストボディの生成
    - `date`: 日付操作（前月・今月の算出）

## 4. スクリプト構成案 (scripts/redmine_rollover.rb)

### 4.1. 接続設定の取得
以下の優先順位で設定を取得します（外部 Gem や `.env` は使用しません）。
1.  コマンドラインオプション (`--redmine-url`, `--redmine-api-key`)
2.  環境変数 (`REDMINE_URL`, `REDMINE_API_KEY`)

### 4.2. 実装ロジック
- `Date.today` から先月（`YYYY-MM`）と今月（`YYYY-MM`）のバージョン名を生成。
- `Net::HTTP` を使用して、Redmine API (JSON) を呼び出し：
    1.  `GET /projects/:project_id/versions.json` でバージョン一覧を取得。
    2.  対象バージョン名から ID を特定。
    3.  `GET /issues.json?fixed_version_id=:old_id&status_id=open` で移行対象チケットを取得。
    4.  `PUT /issues/:issue_id.json` でチケットの `fixed_version_id` を更新。
    5.  `PUT /versions/:old_id.json` で前月バージョンの `status` を `closed` に変更。

## 5. 実行方法
依存ライブラリがないため、Ruby がインストールされていれば即座に実行可能です。

```bash
# プロジェクト識別子を指定して実行する例
ruby scripts/redmine_rollover.rb --project my-project --redmine-url https://redmine.example.com --redmine-api-key your_api_key
```

## 6. 今後のステップ
1.  [ ] Ruby スクリプトのプロトタイプ作成
2.  [ ] テスト用プロジェクトでの動作確認
3.  [ ] GitHub Actions 等による定期実行（Cron）の設定
