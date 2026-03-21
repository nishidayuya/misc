# ```console
# (Measure-Command { .\install_ruby.ps1 -RubyVersion 3.4.8 -Architecture x64 -InstallScope AllUsers }).TotalSeconds
# ```
#
# https://chatgpt.com/c/69a0ff71-c80c-8323-9aa0-bf6ad2829669 で生成

<#
.SYNOPSIS
  Windows Server 2022 等で RubyInstaller を自動ダウンロードし、
  指定バージョン・指定アーキテクチャでサイレントインストールするスクリプト。
  MSYS2 (ridk) の自動初期化も実行します。
  PATH は変更しません。

.PARAMETER RubyVersion
  インストールする Ruby のバージョン（例: 3.4.8）

.PARAMETER Architecture
  x64 または x86 を指定

.PARAMETER InstallScope
  インストール対象
    AllUsers    : すべてのユーザー
    CurrentUser : 現在のユーザーのみ

.EXAMPLE
  全ユーザー向けに Ruby 3.4.8 (x64) をインストール
    .\install_ruby.ps1 -RubyVersion 3.4.8 -Architecture x64 -InstallScope AllUsers

.EXAMPLE
  自分のみ Ruby 3.4.8 (x64) をインストール
    .\install_ruby.ps1 -RubyVersion 3.4.8 -Architecture x64 -InstallScope CurrentUser

.NOTES
  - RubyInstaller (https://github.com/oneclick/rubyinstaller2) を使用
  - ビルド番号 (-1 など) は自動検出
  - 完全非対話インストール
  - 管理者 PowerShell 推奨（AllUsers の場合）
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$RubyVersion,

    [Parameter(Mandatory=$true)]
    [ValidateSet("x64","x86")]
    [string]$Architecture,

    [Parameter(Mandatory=$true)]
    [ValidateSet("AllUsers","CurrentUser")]
    [string]$InstallScope
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Host "=== Ruby $RubyVersion ($Architecture) Installation Start ==="

# GitHub API
$releaseApi = "https://api.github.com/repos/oneclick/rubyinstaller2/releases"
$releases = Invoke-RestMethod -Uri $releaseApi

$targetRelease = $releases | Where-Object {
    $_.tag_name -like "RubyInstaller-$RubyVersion-*"
} | Select-Object -First 1

if (!$targetRelease) {
    throw "RubyInstaller release for version $RubyVersion not found."
}

$asset = $targetRelease.assets | Where-Object {
    $_.name -like "rubyinstaller-$RubyVersion-*$Architecture.exe"
} | Select-Object -First 1

if (!$asset) {
    throw "Installer asset not found."
}

$downloadUrl = $asset.browser_download_url
Write-Host "Downloading: $downloadUrl"

$tempDir = "$env:TEMP\ruby-install"
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
$installerPath = Join-Path $tempDir $asset.name

Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath

# インストールスコープ指定
$scopeArg = if ($InstallScope -eq "AllUsers") {
    "/ALLUSERS"
} else {
    "/CURRENTUSER"
}

Write-Host "Installing Ruby ($InstallScope)..."

$arguments = "/verysilent $scopeArg /tasks=`"assocfiles`""

Start-Process -FilePath $installerPath -ArgumentList $arguments -Wait

Write-Host "Installation finished."

# インストール先検出
$rubyRoot = if ($InstallScope -eq "AllUsers") {
    "C:\"
} else {
    "$env:LOCALAPPDATA"
}

$rubyDir = Get-ChildItem $rubyRoot -Directory |
           Where-Object { $_.Name -like "Ruby*" } |
           Sort-Object LastWriteTime -Descending |
           Select-Object -First 1

if (!$rubyDir) {
    throw "Ruby installation directory not found."
}

$rubyExe = Join-Path $rubyDir.FullName "bin\ruby.exe"
$ridkCmd = Join-Path $rubyDir.FullName "bin\ridk.cmd"

& $rubyExe -v

Write-Host "=== MSYS2 Initialization Start ==="
Start-Process -FilePath $ridkCmd -ArgumentList "install 1 2 3" -Wait -NoNewWindow

Write-Host "=== MSYS2 Initialization Completed ==="
Write-Host "Ruby + MSYS2 installed successfully."