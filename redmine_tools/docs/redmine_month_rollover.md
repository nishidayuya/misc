# Redmine 月次ロールオーバー自動化計画

Redmine の月次運用（チケットの次月移行と旧バージョンのクローズ）を自動化するための設計書です。

## 1. 目的
毎月手動で行っている、前月のバージョン（`YYYY-MM`）から今月のバージョンへのチケット移行作業、および前月バージョンのクローズ作業を自動化し、作業ミスを削減し効率化を図ります。

## 2. 自動化の対象プロセス
1.  **バージョンの特定**: `Date.today` を基準に、先月分（`YYYY-MM`形式）と今月分を自動算出。
2.  **チケットの移行**: 先月のバージョンに割り当てられている未完了のチケットを、すべて今月のバージョンに付け替えます。
3.  **バージョンのクローズ**: 先月のバージョンのステータスを「終了 (Closed)」に変更します。

## 3. 技術スタック
- **言語**: Ruby 3.x
- **標準ライブラリのみ使用**:
    - `optparse`: コマンドライン引数の解析
    - `net/http`, `uri`, `openssl`: Redmine REST API との通信
    - `json`: API レスポンスのパースおよびリクエストボディの生成
    - `date`: 日付操作（前月・今月の算出）

## 4. プログラム仕様 (redmine_rollover)

### 4.1. 引数と設定の取得
プログラムは以下の形式で実行します。

```bash
./redmine_rollover PROJECT_URL [options]
```

- **第一引数 (必須)**: Redmine のプロジェクトURL (例: `https://redmine.example.com/projects/my-project`)
    - プログラム内でこの URL をパースし、「ベース URL」と「プロジェクト識別子」を抽出します。
- **Redmine API キー**: 以下の優先順位で取得します。
    1.  コマンドラインオプション (`--redmine-api-key`)
    2.  環境変数 (`REDMINE_API_KEY`)

### 4.2. プログラムオプション
- `--redmine-api-key KEY`: Redmine API キー

### 4.3. 実装ロジック詳細
- `#! /usr/bin/env ruby` の Shebang を付与。
- `+x` 権限を付与し、直接実行可能にする。
- URL の解析: `URI.parse` を使用して、ホスト名部分（ベースURL）とパスの末尾（プロジェクト識別子）を抽出。
- API 通信：
    1.  `GET /projects/:project_id/versions.json` で、名前が `YYYY-MM`（先月と今月）のバージョンIDを特定。
    2.  `GET /issues.json?project_id=:project_id&fixed_version_id=:old_id&status_id=open` で移行対象の未完了チケットを取得。
    3.  `PUT /issues/:issue_id.json` でチケットの `fixed_version_id` を今月のIDに更新。
    4.  `PUT /versions/:old_id.json` で前月バージョンの `status` を `closed` に変更。

## 5. 実行方法
```bash
# プロジェクトURLを第一引数に指定
./redmine_rollover https://redmine.example.com/projects/my-project --redmine-api-key your_api_key

# APIキーを環境変数で指定する場合
export REDMINE_API_KEY=your_api_key
./redmine_rollover https://redmine.example.com/projects/my-project
```

## 6. 今後のステップ
1.  [ ] Ruby スクリプト `redmine_rollover` の作成
2.  [ ] テスト用プロジェクトでの動作確認
3.  [ ] 定期実行（Cron/CI）の設定
