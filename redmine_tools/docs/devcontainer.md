# Devcontainer 開発環境構築計画

Redmine API を操作する Ruby 製 CLI ツール開発のための Devcontainer 環境を構築します。

## 1. 環境構成 (Devcontainer)

`.devcontainer/devcontainer.json` に以下の構成を定義します。

### ベースイメージ
- **Image**: `mcr.microsoft.com/devcontainers/ruby:3.3`
  - 最新の安定版 Ruby を使用します。

### VS Code 拡張機能 (推奨)
- `rebornix.Ruby`: Ruby 言語サポート
- `misogi.ruby-rubocop`: 静的解析
- `castwide.solargraph`: コード補完・定義ジャンプ
- `kaiwood.endwise`: `end` の自動補完

### 環境変数
Redmine API との通信に必要な情報を環境変数から読み取れるようにします。
- `REDMINE_URL`: Redmine インスタンスの URL
- `REDMINE_API_KEY`: API アクセスキー

## 2. ライブラリ構成 (Gemfile)

CLI ツール開発に便利な以下の Gem を導入します。

- **faraday**: HTTP クライアント（API 通信用）
- **thor**: CLI フレームワーク（コマンドやオプションの定義を容易にする）
- **dotenv**: `.env` ファイルから環境変数を読み込む（開発用）
- **rubocop**: コードスタイル管理
- **rspec**: テストフレームワーク

## 3. 今後の手順

1. **`.devcontainer/` の作成**:
   - `devcontainer.json` を作成し、上記構成を定義する。
2. **`Gemfile` の作成**:
   - 必要なライブラリを記述し、`bundle install` を実行する。
3. **CLI の雛形作成**:
   - `thor` を使った基本的なコマンド構造を作成する。
4. **Redmine API 通信の実装**:
   - `faraday` を使って Redmine の `/issues.json` などにリクエストを投げる処理を実装する。

## 4. 実行・テスト方法

```bash
# 依存関係のインストール
bundle install

# コマンドの実行例 (仮)
REDMINE_URL=https://redmine.example.com REDMINE_API_KEY=your_key ruby exe/redmine-tools list
```
