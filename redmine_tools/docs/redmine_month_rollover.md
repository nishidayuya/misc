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
- **ライブラリ**: `redmine_client` (Redmine REST API クライアント), `dotenv`
- **設定管理**: `.env` ファイル

## 4. スクリプト構成案 (scripts/redmine_rollover.rb)

### 4.1. 接続設定
`.env` ファイルから `REDMINE_URL` と `REDMINE_API_KEY` を読み込みます。

### 4.2. 実装ロジック
- `Date` クラスを使用して、先月（`last_month_version`）と今月（`this_month_version`）の文字列を生成。
- Redmine API で対象プロジェクトの全バージョンを取得。
- `last_month_version` に属するチケットを `this_month_version` に一括更新。
- `last_month_version` オブジェクトのステータスを `closed` に更新。

## 5. 実行環境のセットアップ
1.  依存ライブラリのインストール:
    ```bash
    gem install redmine_client dotenv
    ```
    または `Gemfile` を作成して `bundle install`
2.  `.env` ファイルの作成:
    ```bash
    cp .env.example .env
    # REDMINE_URL と REDMINE_API_KEY を編集
    ```

## 6. 今後のステップ
1.  [ ] Ruby スクリプトのプロトタイプ作成
2.  [ ] テスト用プロジェクトでの動作確認
3.  [ ] GitHub Actions 等による定期実行（Cron）の設定
