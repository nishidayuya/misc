# Devcontainer 開発環境構築計画

Redmine API を操作する Ruby 製 CLI ツール開発のための Devcontainer 環境を構築します。また、開発を支援する Gemini CLI をコンテナ内で利用可能にします。

## 1. 環境構成 (Devcontainer)

`.devcontainer/devcontainer.json` に以下の構成を定義します。

### ベースイメージ
- **Image**: `mcr.microsoft.com/devcontainers/ruby:3.4`
  - 最新の安定版 Ruby を使用します。

### Gemini CLI の利用
コンテナ内で Gemini CLI を動かすために以下の設定を行います。
- **Features**: `ghcr.io/devcontainers/features/node:1` を追加して Node.js をインストール。
- **Post Create Command**: `npm install -g @google/gemini-cli` を実行。
- **環境変数**: `GEMINI_API_KEY` を定義。

#### 設定のマウント
ホスト側の Gemini 設定をコンテナ内でも共有するため、以下のディレクトリをマウントします。
- **マウント先**: `/home/vscode/.gemini`
- **マウント元**: `${localEnv:HOME}/.gemini`
  - ※ 異なるディレクトリを使用したい場合は、ホスト側で `~/.gemini` をシンボリックリンクにするか、`.devcontainer/devcontainer.json` の `source` を手動で書き換えてください。

### 環境変数
- `REDMINE_URL`: 接続先 Redmine の URL
- `REDMINE_API_KEY`: Redmine API アクセスキー
- `GEMINI_API_KEY`: Gemini API キー

## 2. 今後の手順

1. **`.devcontainer/` の作成**:
   - `devcontainer.json` を作成し、Ruby 3.4 イメージ、Node.js Feature、Gemini CLI インストール処理を定義する。
   - `mounts` 設定を追加して、Gemini の設定ディレクトリをリンクする。
2. **`.env` ファイルの用意**:
   - `REDMINE_URL`, `REDMINE_API_KEY`, `GEMINI_API_KEY` を設定する。
3. **CLIツールの実装**:
   - Ruby 3.4 を使用して Redmine API 連携処理を実装する。

## 3. 実行・テスト方法

```bash
# Gemini CLI の動作確認（マウントされた設定が反映されているか）
gemini config list

# Ruby のバージョン確認
ruby --version
```
