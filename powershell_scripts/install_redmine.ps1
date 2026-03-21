# ```console
# gem install pg -v 1.5.9 -- --with-pg-config="C:/Program Files/PostgreSQL/14/bin/pg_config.exe"
# (Measure-Command { .\install_redmine.ps1 -RedmineVersion "6.1.1" -DatabaseUrl "postgresql://postgres:redminepassword@127.0.0.1/redmine61" -RubyPath "C:\Ruby34-x64\bin" }).TotalSeconds
# ```
#
# https://chatgpt.com/c/69a1053f-fb7c-8321-91bf-6ba79b509cd5 で生成

<#
===============================================================================
Redmine 自動インストールスクリプト
Windows Server 2022 + Ruby + PostgreSQL 対応（pg事前インストール前提）

■ 概要
  指定した Ruby パス・Redmine バージョン・Database URL を使用して
  Redmine を C:\redmine-<バージョン> にインストールします。

  ※ pg gem は事前にインストール済みであること
     例: gem install pg

  既に C:\redmine-<バージョン> が存在する場合は何もせず終了します。

■ 実行例
  .\install_redmine.ps1 `
    -RubyPath "C:\Ruby34-x64\bin" `
    -RedmineVersion "6.1.1" `
    -DatabaseUrl "postgresql://redmine:redminepassword@localhost/redmine61"
===============================================================================
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$RubyPath,

    [Parameter(Mandatory=$true)]
    [string]$RedmineVersion,

    [Parameter(Mandatory=$true)]
    [string]$DatabaseUrl
)

$ErrorActionPreference = "Stop"

$InstallDir  = "C:\redmine-$RedmineVersion"
$DownloadUrl = "https://www.redmine.org/releases/redmine-$RedmineVersion.tar.gz"
$ArchivePath = "C:\redmine-$RedmineVersion.tar.gz"

# ===============================
# 既存チェック
# ===============================
if (Test-Path $InstallDir) {
    Write-Host "Redmine $RedmineVersion already exists. Nothing to do."
    exit 0
}

# ===============================
# Ruby PATH追加
# ===============================
$env:PATH = "$RubyPath;$env:PATH"

# ===============================
# ダウンロード
# ===============================
Write-Host "Downloading Redmine $RedmineVersion..."
Invoke-WebRequest -Uri $DownloadUrl -OutFile $ArchivePath

# ===============================
# 解凍
# ===============================
Write-Host "Extracting archive..."
tar -xzf $ArchivePath -C C:\

if (!(Test-Path $InstallDir)) {
    throw "Extraction failed."
}

Set-Location $InstallDir

# ===============================
# Gemfile.local 作成（puma追加）
# ===============================
Write-Host "Creating Gemfile.local..."
@"
gem "puma"
"@ | Out-File -Encoding UTF8 "$InstallDir\Gemfile.local"

# ===============================
# database.yml 作成（値をダブルクォート）
# ===============================
Write-Host "Creating database.yml..."
@"
production:
  adapter: "postgresql"  # https://github.com/redmine/redmine/blob/6.1.1/Gemfile#L69 より必要
  url: "$DatabaseUrl"
"@ | Out-File -Encoding UTF8 "$InstallDir\config\database.yml"

# ===============================
# Bundler
# ===============================
Write-Host "Installing bundler..."
gem install bundler --no-document

bundle config set --local without 'development test'

Write-Host "Running bundle install..."
bundle install

# ===============================
# Rails 環境
# ===============================
$env:RAILS_ENV = "production"

# ===============================
# secret token
# ===============================
Write-Host "Generating secret token..."
bundle exec rails generate_secret_token

# ===============================
# DB 作成
# ===============================
Write-Host "Creating database..."
bundle exec rails db:create

# ===============================
# DB migrate
# ===============================
Write-Host "Running database migration..."
bundle exec rails db:migrate

# ===============================
# 初期データ投入（指定どおり）
# ===============================
Write-Host "Loading default data..."
bundle exec rails redmine:load_default_data REDMINE_LANG=ja

Write-Host "======================================="
Write-Host "Redmine installation completed!"
Write-Host "Location: $InstallDir"
Write-Host "======================================="
