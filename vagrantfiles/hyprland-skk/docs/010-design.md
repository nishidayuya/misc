# hyprland-skk 設計書

## 1. 目的とスコープ

Debian GNU/Linux 13 (trixie) の libvirt VM 上に Hyprland のデスクトップを構築し、
SKK で日本語入力ができる環境を Vagrant で再現可能にする。

- Emacs は DDSKK（Emacs 内蔵の入力方式）で入力する。
- それ以外の GUI アプリケーション（Ghostty / Chromium / GNOME テキストエディター）は
  Fcitx5 + SKK で入力する。
- Wayland ネイティブで動かす。`GDK_BACKEND=x11` と `--ozone-platform=x11` は使わない。

### 今回の完了条件

自動的に確認できる範囲は次の 2 つに限る。

1. `vagrant up` が最後まで成功する。
2. `vagrant ssh` でログインできる。

GUI が実際に表示され日本語入力できることの確認は VNC 経由の目視で行う（第 8 章）。
これは対話的な操作が必要なため、今回の繰返し修正ループの終了条件には含めない。

## 2. 前提環境と制約

作業は `vagrantfiles/.devcontainer` の Dev Container 内で行う。ここには次の制約がある。

| 項目 | 内容 |
| --- | --- |
| プロバイダー | `VAGRANT_DEFAULT_PROVIDER=libvirt`（`devcontainer.json` の `containerEnv`） |
| 同期フォルダー | `VAGRANT_SYNCED_FOLDER_TYPE=9p`（同上） |
| ストレージプール | `post_start_command.d/40-libvirt` が `default` プールを `/var/lib/libvirt/images` に作成 |
| VM への到達 | `45-vagrant-vm-access` が `192.168.121.0/24` を許可 |
| VM の外向き通信 | `46-vagrant-vm-egress` が `allow_hosts.d` と同じ allowlist に制限。**53/80/443 のみ** |

VM が使えるホストのうち、本設計に関係するものは次のとおり。いずれも既に許可済み。

- `deb.debian.org` / `security.debian.org` … `30-debian`（trixie-backports も同じホスト）
- `github.com` / `objects.githubusercontent.com` … `00-github`
- `mise.run` … `91-vagrant-guest`、`mise.jdx.dev` … `50-mise`

**未確認事項**: GitHub Release のアセットは配布元が
`release-assets.githubusercontent.com` に変わっている場合がある。Ghostty の AppImage 取得が
`connection refused` で失敗したら `allow_hosts.d` への追加が必要になる（第 9 章）。

## 3. ディレクトリー構成

```
hyprland-skk/
├── .gitignore                     # /.vagrant
├── Vagrantfile
├── docs/
│   └── 010-design.md              # この文書
└── provision_scripts/
    ├── 010-install_ja_JP_locale
    ├── 020-enable_backports
    ├── 030-install_hyprland
    ├── 040-install_fcitx5_skk
    ├── 050-install_emacs_ddskk
    ├── 060-install_mise            -> ../../_common/libexec/install_mise
    ├── 070-install_ghostty_by_mise
    ├── 080-install_gui_applications
    ├── 090-install_waybar
    ├── 100-install_wofi
    ├── 110-configure_hyprland
    └── 120-enable_autologin
```

`run-parts` はファイル名にドットを含むものを無視するので、拡張子は付けない。
既存の `mise/` `redmine61/` と同じく、共通処理は `_common/libexec` への symlink で持つ。

**注意**: `_common/libexec/install_ja_JP_locale` は `language-pack-ja` を入れており、
これは Ubuntu 専用パッケージなので Debian では使えない。`010-install_ja_JP_locale` は
`locales` パッケージ + `/etc/locale.gen` 編集 + `locale-gen` で独自に実装する。

## 4. Vagrantfile

`redmine61/Vagrantfile` の構造（`env_or_default`、`run-parts` への委譲）と
`mise/Vagrantfile` の libvirt 対応（9p、読み取り専用同期フォルダーの分岐）を踏襲する。

```ruby
# -*- mode: ruby -*-
# vi: set ft=ruby :

def env_or_default(env_name, default)
  env_value = ENV.fetch(env_name, "")
  return env_value.empty? ? default : env_value
end

ENV["VAGRANT_DEFAULT_PROVIDER"] = env_or_default("VAGRANT_DEFAULT_PROVIDER", "libvirt")
synced_folder_type = env_or_default("VAGRANT_SYNCED_FOLDER_TYPE", "9p")

read_only_synced_folder_options =
  if synced_folder_type == "9p"
    {readonly: true, mount_opts: "ro"}
  else
    {mount_options: %w[ro]}
  end

n_cpus = ENV.fetch("VAGRANT_CPUS") {
  require "etc"
  [2, Etc.nprocessors / 2].max
}
memory_mega_bytes = ENV.fetch("VAGRANT_MEMORY", 1024 * 8).to_i
graphics_port = ENV.fetch("VAGRANT_GRAPHICS_PORT", 5910).to_i

Vagrant.configure("2") do |config|
  config.vm.box = "debian/trixie64"
  config.vm.box_version = "13.20260519.1"

  config.vm.synced_folder(".", "/vagrant", type: synced_folder_type)
  config.vm.synced_folder("../_common", "/_common",
                          type: synced_folder_type,
                          **read_only_synced_folder_options)

  config.vm.provider(:libvirt) do |libvirt|
    libvirt.cpus = n_cpus
    libvirt.memory = memory_mega_bytes

    # cirrus（vagrant-libvirt の既定値）は VRAM 4MB 固定で 1024x768 程度が上限。
    # virtio-gpu はゲストが要求したモードをそのままホストに伝えるので、解像度の
    # 制約が実質なくなる。3D アクセラレーション（virgl）は有効にしない: SPICE と
    # graphics_gl が前提になり、GL 有効の SPICE は TCP で待ち受けできないため、
    # コンテナー外から見る用途と両立しない。描画は llvmpipe に任せる。
    libvirt.video_type = "virtio"

    # 既定値は 127.0.0.1 とランダムポート。コンテナーの外から VNC で覗くために、
    # 待ち受けアドレスとポートを固定する。
    libvirt.graphics_type = "vnc"
    libvirt.graphics_ip = "0.0.0.0"
    libvirt.graphics_port = graphics_port
  end

  config.vm.provision(:shell, privileged: false, inline: <<~SHELL)
    set -eux -o pipefail

    export DEBIAN_FRONTEND=noninteractive

    exec run-parts --verbose --exit-on-error /vagrant/provision_scripts
  SHELL
end
```

`:virtualbox` プロバイダーのブロックは置かない。VirtualBox には virtio-gpu が無く、
Hyprland を動かす前提が成立しないため、この Vagrantfile は libvirt 専用とする。

## 5. provision_scripts の設計

### 010-install_ja_JP_locale

`locales` を入れ、`ja_JP.UTF-8 UTF-8` を `/etc/locale.gen` に追加して `locale-gen`。
`localectl list-locales` で確認する。日本語フォント（`fonts-noto-cjk`）もここで入れる。
フォントが無いと Chromium も Ghostty も日本語が豆腐になり、入力の確認ができない。

### 020-enable_backports

Debian 13 の APT は deb822 形式なので、`/etc/apt/sources.list.d/debian-backports.sources` を
新規に置く。

```
Types: deb
URIs: http://deb.debian.org/debian
Suites: trixie-backports
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
```

backports は既定では優先度が低く自動では選ばれないので、後続では明示的に
`apt-get install -t trixie-backports ...` を使う。

### 030-install_hyprland

`apt-get install -t trixie-backports hyprland` でインストールする
（trixie-backports の版は 0.55.2+ds-1~bpo13+1）。あわせて次を入れる。

- `libgl1-mesa-dri` … llvmpipe 側の実体。virtio-gpu には virgl を入れないので
  Mesa は `kms_swrast` にフォールバックする。
- `xdg-desktop-portal-hyprland`、`xdg-desktop-portal-gtk`
- `foot` などの保険用端末は入れない（Ghostty が動かないときの切り分けは
  `vagrant ssh` 側で行う）。

### 040-install_fcitx5_skk

`fcitx5`、`fcitx5-skk`、`fcitx5-config-qt`、`skkdic` を APT で入れる。
GTK / Qt の IM モジュール（`fcitx5-frontend-gtk4` など）は **入れない**。
理由は第 6 章。

設定ファイルは provisioning で直接書く（初回起動時の対話設定を避けるため）。

- `~/.config/fcitx5/profile` … `[Groups/0/Items/0] Name=keyboard-us` と
  `[Groups/0/Items/1] Name=skk` を並べ、既定の入力メソッドに SKK を登録する。
- `~/.config/fcitx5/conf/skk.conf` … 辞書に `/usr/share/skk/SKK-JISYO.L` を指定する。

### 050-install_emacs_ddskk

`emacs-pgtk` と `elpa-ddskk` を APT で入れる。`emacs-gtk` ではなく `emacs-pgtk` を
選ぶのは、後者が Wayland ネイティブ（pure GTK）ビルドで、XWayland を経由しないため。

`~/.emacs.d/init.el` に最小限の DDSKK 設定を書く。

```elisp
(setq default-input-method "japanese-skk")
(setq skk-large-jisyo "/usr/share/skk/SKK-JISYO.L")
(global-set-key (kbd "C-x C-j") 'skk-mode)
```

Emacs では Fcitx5 を使わない。Emacs は DDSKK 自身が入力を処理するので、
Fcitx5 を併用すると変換が二重になる。フォーカスが Emacs にあるときは
Fcitx5 を無効にしておく運用とする。

Emacs Client をメニューから起動するため、`systemctl --user enable --now emacs` で
デーモンを常駐させる（Debian の `emacs-common` が user unit を提供しているかは
provisioning 時に確認し、無ければ `~/.config/systemd/user/emacs.service` を自作する）。

### 060-install_mise

`_common/libexec/install_mise` への symlink。`curl https://mise.run | sh` で
`~/.local/bin/mise` に入る。

### 070-install_ghostty_by_mise

Ghostty は mise のレジストリーに短縮名が無い（`mise registry` に `ghostty` は無い）。
AppImage を GitHub Release から取る backend 指定で入れる。

```sh
mise use --global "github:pkgforge-dev/ghostty-appimage"
```

AppImage の実行には FUSE が要るので `libfuse2t64` を APT で入れる。入らない/動かない
場合は `APPIMAGE_EXTRACT_AND_RUN=1` を環境変数で与える方針に切り替える。

`.desktop` ファイルが付いてこないので、`~/.local/share/applications/ghostty.desktop` を
自分で用意する。`Exec` は mise の shim ではなくフルパスの wrapper を指す。

```
[Desktop Entry]
Type=Application
Name=Ghostty
Exec=/usr/local/bin/ghostty
Terminal=false
Categories=System;TerminalEmulator;
```

`/usr/local/bin/ghostty` は `exec /home/vagrant/.local/bin/mise exec -- ghostty "$@"` の
1 行ラッパー。Hyprland のキーバインドからも wofi からも同じものを起動できるようにする。

### 080-install_gui_applications

`chromium` と `gnome-text-editor` を APT で入れる。

Chromium の Wayland / IME フラグは、Debian の launcher が `/etc/chromium.d/*` を
source する仕組みを使って設定する（`/usr/bin/chromium` が実際にそうしている）。

`/etc/chromium.d/wayland-ime`:

```sh
export CHROMIUM_FLAGS="$CHROMIUM_FLAGS --ozone-platform=wayland"
export CHROMIUM_FLAGS="$CHROMIUM_FLAGS --enable-wayland-ime"
export CHROMIUM_FLAGS="$CHROMIUM_FLAGS --wayland-text-input-version=3"
```

`--ozone-platform=x11` は使わない。Chromium は `--enable-wayland-ime` と
text-input のバージョン指定で Wayland のまま IME を受け取れる。

GNOME テキストエディターは GTK4 なので追加設定は不要（第 6 章の方針がそのまま効く）。

### 090-install_waybar

`waybar` を APT で入れ、Hyprland の `exec-once` から起動する。設定は Debian 同梱の
`/etc/xdg/waybar/` をそのまま使い、必要なら後から `~/.config/waybar/` に持ってくる。

### 100-install_wofi

`wofi` を APT で入れる。メニューは `wofi --show drun` で `.desktop` ファイルから作る。
`Super+R` で起動する。並ぶべき 4 つの起動項目は次のとおり。

| 項目 | `.desktop` の出どころ |
| --- | --- |
| Emacs Client | 自作（`emacsclient -c -a emacs`） |
| Ghostty | 自作（070 で作成） |
| Chromium | `chromium` パッケージ同梱 |
| テキストエディター | `gnome-text-editor` パッケージ同梱 |

自作分は `~/.local/share/applications/` に置く。

### 110-configure_hyprland

`~/.config/hypr/hyprland.conf` を生成する。要点だけ示す。

```
monitor = Virtual-1, 1920x1080@60, 0x0, 1

# 日本語入力: GTK_IM_MODULE / QT_IM_MODULE はあえて設定しない（第 6 章）
env = XMODIFIERS,@im=fcitx
env = LIBGL_ALWAYS_SOFTWARE,1

exec-once = fcitx5 -d
exec-once = waybar

bind = SUPER, Q, exec, /usr/local/bin/ghostty
bind = SUPER, R, exec, wofi --show drun

# llvmpipe で描くので、重い演出は切る
animations { enabled = false }
decoration { blur { enabled = false } shadow { enabled = false } }
misc { vfr = true }
```

`Virtual-1` は virtio-gpu の DRM コネクター名。実機名は `hyprctl monitors` で確認して
合わせる。`LIBGL_ALWAYS_SOFTWARE` は保険であり、virtio-gpu 上で Mesa が自動的に
`kms_swrast` を選ぶなら不要。動作確認後に外すかどうか判断する。

### 120-enable_autologin

**ここが Hyprland を動かすうえでの肝**。Hyprland は DRM のマスターを取るために
seat を持つセッションが要る。SSH のセッションには seat が無いので、`vagrant ssh` から
`Hyprland` を叩いても起動しない。tty1 に自動ログインし、そこから起動する。

- `/etc/systemd/system/getty@tty1.service.d/override.conf` で
  `agetty --autologin vagrant` にする。
- `~/.bash_profile` に「tty1 かつ `WAYLAND_DISPLAY` 未設定なら `exec Hyprland`」を追加する。

provisioning 後に `sudo systemctl daemon-reload && sudo systemctl restart getty@tty1` で
反映する（`vagrant reload` でもよい）。

開発用 VM に限った設定であり、本番環境には流用しない。

## 6. 日本語入力の設計

Wayland の `text-input-v3` に一本化する。Fcitx5 の Wayland フロントエンドは既定で
有効で、GTK / Qt は IM モジュールが明示指定されていなければ text-input を使う。

| 環境変数 | 値 | 理由 |
| --- | --- | --- |
| `GTK_IM_MODULE` | **設定しない** | 未設定だと GTK3/GTK4 が内蔵の Wayland IM モジュールを使う。Ghostty は AppImage で GTK を同梱しており、システム側の `fcitx5-frontend-gtk4` は読めない。text-input-v3 ならプロトコルだけで完結するのでこの問題が無い |
| `QT_IM_MODULE` | **設定しない** | 同上 |
| `XMODIFIERS` | `@im=fcitx` | XWayland アプリ用。今回の 4 つはすべて Wayland ネイティブなので実際には使われないが、害が無いので残す |

`GDK_BACKEND=x11` / `--ozone-platform=x11` を使わない方針は、この構成と整合している。
X11 に落とすと IM モジュール経由の入力になり、上記の AppImage 問題が再発するうえ、
XWayland 上での描画になって virtio-gpu + llvmpipe の負荷も増える。

既知の弱点として、GTK の text-input-v3 実装は preedit の表示が素朴（太字ハイライト
程度）である。入力自体は成立するので今回は許容する。どうしても駄目なら
`fcitx5-frontend-gtk4` を入れて `GTK_IM_MODULE=fcitx` に切り替えるが、その場合
Ghostty の AppImage だけは別途対処が必要になる。

## 7. Emacs と Fcitx5 の棲み分け

| アプリケーション | 入力方式 | 備考 |
| --- | --- | --- |
| Emacs (emacs-pgtk) | DDSKK | `C-x C-j` で SKK モード |
| Ghostty | Fcitx5-SKK | GTK4 / text-input-v3 |
| Chromium | Fcitx5-SKK | `--enable-wayland-ime` |
| GNOME テキストエディター | Fcitx5-SKK | GTK4 / text-input-v3 |

## 8. 画面の見かた

```
Hyprland → virtio-gpu (DRM: Virtual-1)
         → QEMU が VNC でフレームバッファーを提供 (0.0.0.0:5910, コンテナー内)
         → Dev Container のポート転送
         → 手元の VNC クライアント
```

確認コマンド:

```sh
virsh -c qemu:///system list
virsh -c qemu:///system vncdisplay <domain>
```

うまくいかない場合の代替として、ゲスト内に `wayvnc` を入れて
`vagrant ssh -- -L 5900:127.0.0.1:5900` で SSH トンネル越しに見る方法がある。
こちらは Hyprland の headless 出力を別途作る必要があり手数が多いので、第一候補にはしない。

## 9. Dev Container への変更

必要になる見込みのもの。実際に `vagrant up` を回して、必要だと確認できたものだけ入れる。

1. **`devcontainer.json` にポート転送を追加**（VNC で見るために必須）
   `"forwardPorts": [5910]` を追加する。DevPod でも効かせるなら `appPort` を使う。
   どちらもコンテナーの再作成が要る。
2. **`allow_hosts.d` の追加**（Ghostty の取得が失敗した場合のみ）
   `91-vagrant-guest` に `release-assets.githubusercontent.com` を追加する。
   `00-github` が持っている GitHub の IP レンジには `*.githubusercontent.com` が
   含まれないため、Release アセットの配布元が変わっているとここで止まる。
3. 上記以外は不要と考えている。VNC はコンテナー内の libvirt が listen し、
   `00-firewall` は INPUT を制限していないので、受信側の追加ルールは要らない。

コミットは `feat(devcontainer): ...` として Vagrantfile 側とは分けて積む。

## 10. 検証手順

```sh
cd /workspaces/misc/vagrantfiles/hyprland-skk
vagrant up                      # 完走すること
vagrant ssh -c 'true'           # ログインできること
```

失敗したら原因を直してコミットし、`vagrant destroy -f && vagrant up` で
最初からやり直す。これを通るまで繰返す。

通ったあとに手動で確認する項目（今回の完了条件には含めない）。

- [ ] VNC で Hyprland の画面が見える
- [ ] waybar が上部に出ている
- [ ] `Super+Q` で Ghostty が起動する
- [ ] `Super+R` で wofi が出て、4 つの項目が並んでいる
- [ ] Ghostty / Chromium / GNOME テキストエディターで Fcitx5-SKK による入力ができる
- [ ] Emacs で `C-x C-j` から DDSKK による入力ができる

補助的な確認コマンド（`vagrant ssh` から）:

```sh
hyprctl monitors                # Virtual-1 と解像度
hyprctl clients                 # 起動中のウィンドウ
fcitx5-diagnose                 # IM の状態一式
journalctl --user -u emacs      # Emacs デーモン
```

## 11. コミット計画

1. `feat(hyprland-skk): add a Vagrantfile that boots Debian GNU/Linux 13 on libvirt`
2. `feat(hyprland-skk): install Hyprland from trixie-backports`
3. `feat(hyprland-skk): install Emacs with DDSKK`
4. `feat(hyprland-skk): install Fcitx5 SKK for Wayland applications`
5. `feat(hyprland-skk): install Ghostty via mise`
6. `feat(hyprland-skk): install Chromium and GNOME Text Editor`
7. `feat(hyprland-skk): install waybar and wofi`
8. `feat(hyprland-skk): start Hyprland on tty1 automatically`
9. `feat(devcontainer): ...`（必要が確認できた場合のみ）

途中で見つかった修正は、対応するコミットに `fix(hyprland-skk): ...` として積む。

## 12. リスクと代替案

| リスク | 影響 | 代替案 |
| --- | --- | --- |
| llvmpipe の描画が重い | Chromium のスクロールなどが遅い | 解像度を 1280x800 に落とす。アニメーション・blur は既に無効 |
| Ghostty の AppImage が FUSE 無しで動かない | `Super+Q` が無反応 | `APPIMAGE_EXTRACT_AND_RUN=1` を wrapper に入れる |
| GitHub Release の配布元が allowlist 外 | 070 で provisioning が止まる | 第 9 章の 2 を実施 |
| GTK の text-input-v3 で preedit が見にくい | 入力はできるが体験が悪い | `fcitx5-frontend-gtk4` + `GTK_IM_MODULE=fcitx` に切り替え（Ghostty は別途対処） |
| tty1 自動ログインの反映に再起動が要る | provisioning 直後は Hyprland が出ていない | `vagrant reload` を手順に含める |
| `emacs` の user unit が Debian に無い | Emacs Client がメニューから起動しない | `~/.config/systemd/user/emacs.service` を自作する |
