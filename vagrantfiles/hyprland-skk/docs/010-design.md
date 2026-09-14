# hyprland-skk 設計書

## 1. 目的とスコープ

Debian GNU/Linux 13 (trixie) の libvirt VM 上に Hyprland のデスクトップを構築し、
SKK で日本語入力ができる環境を Vagrant で再現可能にする。

- Emacs は DDSKK（Emacs 内蔵の入力方式）で入力する。
- それ以外の GUI アプリケーション（Ghostty / Chromium / GNOME テキストエディター）は
  Fcitx5 + SKK で入力する。
- Wayland ネイティブで動かす。`GDK_BACKEND=x11` と `--ozone-platform=x11` は使わない。

### 今回の完了条件

1. `vagrant up` が最後まで成功する。
2. `vagrant ssh` でログインできる。
3. 画面とキーボード操作の確認（第 10 章の表）がすべて通る。
4. **`vagrant destroy -f` して作り直した回で、1 から 3 が何も手を加えずに通る。**

3 は人が VNC クライアントを操作しなくてよい。`virsh screenshot` で画面を PNG として
取り出し、`virsh send-key` でキーを送れるので、GDM のログインから日本語入力まで
コンテナー内で自動的に確認できる（第 8 章）。よって繰返し修正ループの終了条件に含める。

4 は、開発中の修正を `vagrant provision` や VM 内の手作業で当ててしまっていないか、
`provision_scripts` だけで同じ状態が再現できるかを見るためのもの。ここで期待と違えば
直してコミットし、また destroy からやり直す（第 10 章の手順 3）。

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

一方、Ghostty をソースからビルドするために次の 2 つが新たに必要になる。**どちらも
現在の allowlist に無い**ので、`allow_hosts.d` への追加が前提になる（第 9 章）。

- `release.files.ghostty.org` … Ghostty のソース tarball と minisig の配布元
- `ziglang.org` … mise の `core:zig` が取得する Zig コンパイラーの配布元

## 3. ディレクトリー構成

```
hyprland-skk/
├── .gitignore                     # /.vagrant
├── Vagrantfile
├── bin/
│   └── screenshot                 # 画面確認用のラッパー（第 8 章）
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
    ├── 120-install_gdm
    ├── 130-enable_gdm_autologin
    └── 140-start_graphical_target
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

Ghostty は mise 自身のレジストリーには無いが、asdf のコミュニティープラグイン
`asdf:ghostty`（実体は `ilvez/asdf-ghostty`）が使える。コンテナー内で
`mise ls-remote asdf:ghostty` が 1.3.1 までのバージョンを返すことを確認済み。

プラグインの追加は、既存の `mise/provision_scripts/025-install_git_by_mise` と同じく
git URL を明示する形を採る。短縮名だけの `mise plugin install ghostty` は、この
コンテナーの allowlist 下では解決に失敗した。

```sh
mise plugin install ghostty https://github.com/ilvez/asdf-ghostty
mise use --global "zig@0.15.2"
mise use --global "ghostty@1.3.1"
```

**このプラグインはバイナリーを配らず、ソースから `zig build` する**。そのため次が要る。

- **Zig 0.15.2**。Ghostty 1.3.1 の `build.zig.zon` が `minimum_zig_version = "0.15.2"` を
  宣言している。プラグイン側の `get_required_zig_version()` は 1.2.x までしか対応表を
  持たず 1.3.x では空を返す（警告が出るだけでビルドは進む）ので、Zig のバージョンは
  こちらで固定する。`latest` ではなく版を打っておくのは、この対応関係が版ごとに
  変わるため。
- **GTK4 まわりのビルド依存**。trixie には必要なものが揃っている
  （`blueprint-compiler` 0.16.0、`gtk4-layer-shell` 1.0.4）。

```sh
sudo apt-get install -y --no-install-recommends \
  build-essential pkg-config git gettext libxml2-utils \
  libgtk-4-dev libadwaita-1-dev libgtk4-layer-shell-dev blueprint-compiler
```

ビルドは数分から十数分かかる。`vagrant up` の所要時間はここが支配的になる。

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
`右Alt+R` で起動する。並ぶべき 4 つの起動項目は次のとおり。

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

# X11 由来の modmask は左右の Alt を区別しないので、右 Alt を
# ISO_Level3_Shift（MOD5）にして専用のマスクを与える
input { kb_options = lv3:ralt_switch }

bind = MOD5, Q, exec, /usr/local/bin/ghostty
bind = MOD5, R, exec, wofi --show drun

# llvmpipe で描くので、重い演出は切る
animations { enabled = false }
decoration { blur { enabled = false } shadow { enabled = false } }
misc { vfr = true }
```

`Virtual-1` は virtio-gpu の DRM コネクター名。実機名は `hyprctl monitors` で確認して
合わせる。`LIBGL_ALWAYS_SOFTWARE` は保険であり、virtio-gpu 上で Mesa が自動的に
`kms_swrast` を選ぶなら不要。動作確認後に外すかどうか判断する。

### 120-install_gdm

`gdm3` を APT で入れ、GDM でログインしてから Hyprland を起動する。

Hyprland は DRM のマスターを取るために seat を持つセッションを必要とする。SSH の
セッションには seat が無いので、`vagrant ssh` から `Hyprland` を叩いても起動しない。
GDM は logind のセッションを seat0 付きで作るので、この問題がディスプレイマネージャー
側で解決する。

- `apt-get install -y gdm3`
- `systemctl set-default graphical.target`
  （Vagrant の box は `multi-user.target` 既定なので明示的に切り替える）
- セッション定義は `hyprland` パッケージ同梱の
  `/usr/share/wayland-sessions/hyprland.desktop` をそのまま使う。
- `/var/lib/AccountsService/users/vagrant` に `[User] Session=hyprland` を書き、
  GDM が既定で Hyprland セッションを選ぶようにする。毎回歯車アイコンから選ばずに済む。

ログインに使う資格情報は Vagrant box 既定の `vagrant` / `vagrant`。ただし既定では
次の 130 が自動ログインを有効にするので、通常この入力は要らない。

GDM 導入後は `graphical.target` に入り直す必要があるので、provisioning の最後で
`vagrant reload` するか `sudo systemctl isolate graphical.target` を実行する。

開発用 VM に限った設定であり、本番環境には流用しない。

### 130-enable_gdm_autologin

GDM の自動ログインを有効にする。`vagrant up` のあと何も操作しなくても Hyprland の
セッションまで到達するので、第 10 章の画面確認が短くなり、llvmpipe で重いグリーターを
毎回描かせずに済む。

`/etc/gdm3/daemon.conf` の `[daemon]` セクションに次の 2 行を入れる（既に書かれて
いれば書き換える）。Debian の gdm3 にはドロップインのディレクトリーが無いので、
ファイルそのものを編集する。

```
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=vagrant
```

**120 と分けているのは、自動ログインだけを外せるようにするため。** 外すときは
`.devcontainer/post_start_command.d/46-vagrant-vm-egress` と同じ手で、実行権限を落とす。

```sh
chmod -x provision_scripts/130-enable_gdm_autologin
```

`run-parts` はそれ以降このスクリプトを飛ばすので、120 までで作った GDM は
そのまま残り、ログイン画面が出るようになる。既に作成済みの VM に効かせるには
`vagrant destroy -f && vagrant up` で作り直す。

自動ログインが効くのは起動直後の 1 回だけで、いちどログアウトするとグリーターが
出る。これは GDM の仕様であり、`vagrant` / `vagrant` でログインすればよい。

開発用 VM に限った設定であり、本番環境には流用しない。

### 140-start_graphical_target

`graphical.target` に入り直し、display manager を起動する。

120 が既定のターゲットを変えても、その時点で動いている VM は切り替わらない。これが
無いと `vagrant up` はテキストコンソールのまま終わり、デスクトップは誰かが再起動する
まで出てこない。

`systemctl isolate graphical.target` だけでは足りなかった。`graphical.target` が既に
active になっている場合があり、そのとき display manager は起動されないまま残る
（ターゲットが display manager を引き込むのは「起動する瞬間」だけで、gdm3 の
インストールが置いた `/etc/systemd/system/display-manager.service` を後から拾い直す
ことはない）。`display-manager.service` を名指しで起動する。

130 の後に置くのは意図的で、自動ログインの設定を書く前に GDM を起動すると
グリーターが出たまま止まるため。

## 6. 日本語入力の設計

Wayland の `text-input-v3` に一本化する。Fcitx5 の Wayland フロントエンドは既定で
有効で、GTK / Qt は IM モジュールが明示指定されていなければ text-input を使う。

| 環境変数 | 値 | 理由 |
| --- | --- | --- |
| `GTK_IM_MODULE` | **設定しない** | 未設定だと GTK3/GTK4 が内蔵の Wayland IM モジュールを使う。Fcitx5 の Wayland フロントエンドは既定で有効で、コンポジターのプロトコルだけで完結するため、アプリケーションごとに IM モジュールを配る必要が無い |
| `QT_IM_MODULE` | **設定しない** | 同上 |
| `XMODIFIERS` | `@im=fcitx` | XWayland アプリ用。今回の 4 つはすべて Wayland ネイティブなので実際には使われないが、害が無いので残す |

`GDK_BACKEND=x11` / `--ozone-platform=x11` を使わない方針は、この構成と整合している。
X11 に落とすと XWayland 上での描画になり、virtio-gpu + llvmpipe の負荷が増える。

既知の弱点として、GTK の text-input-v3 実装は preedit の表示が素朴（太字ハイライト
程度）である。入力自体は成立するので今回は許容する。どうしても駄目なら
`fcitx5-frontend-gtk4` を入れて `GTK_IM_MODULE=fcitx` に切り替える。Ghostty は
システムの GTK4 にリンクしてビルドするので、この切り替えは 3 つの GTK アプリケーション
すべてに同じように効く。

## 7. Emacs と Fcitx5 の棲み分け

| アプリケーション | 入力方式 | 備考 |
| --- | --- | --- |
| Emacs (emacs-pgtk) | DDSKK | `C-x C-j` で SKK モード |
| Ghostty | Fcitx5-SKK | GTK4 / text-input-v3 |
| Chromium | Fcitx5-SKK | `--enable-wayland-ime` |
| GNOME テキストエディター | Fcitx5-SKK | GTK4 / text-input-v3 |

## 8. 画面の見かた

画面には 2 つの経路で到達できる。動作確認は (a) だけで完結する。

### (a) libvirt 経由（自動確認に使う）

QEMU 自身がフレームバッファーを持っているので、VNC クライアントを介さずに
libvirt の API から画面を取り出せる。`virsh` はコンテナーに既に入っている。

```sh
domain=hyprland-skk_default

# 画面を撮る。libvirt 11.3 + QEMU 10.0 の組合せでは image/png が返る見込みなので
# そのまま読める（PPM が返った場合は第 9 章の 3 を実施する）
virsh screenshot "${domain}" --file /tmp/hyprland-skk.png

# キーを送る。codeset は既定の linux なので KEY_* の名前がそのまま使える
virsh send-key "${domain}" KEY_RIGHTALT KEY_Q                    # 右Alt+Q
virsh send-key "${domain}" KEY_RIGHTALT KEY_R                    # 右Alt+R
virsh send-key "${domain}" --holdtime 50 KEY_LEFTCTRL KEY_SPACE  # Fcitx5 の切り替え
```

`bin/screenshot` は上を包んで連番のファイル名で `/tmp` に落とし、撮ったパスを表示する
だけのラッパー。確認の記録がそのまま残る。

できること・できないこと:

- キーボード入力は evdev のイベントとしてゲストに届くので、GDM のログインも
  Hyprland のキーバインドも wofi の絞り込みも SKK の入力も、すべて送れる。
- `virsh send-key` に渡した複数のキーコードは**同時押し**になる。文字列を打つには
  1 文字につき 1 回呼ぶ。
- **ポインターは送れない**。`virsh` にマウスイベントの API が無い。確認手順は
  キーボードだけで到達できるように組む（GDM も wofi もそれで足りる）。
- 画面が消灯していると真っ黒が撮れる。撮る前に無害なキー（`KEY_LEFTSHIFT` など）を
  送って起こす。

### (b) VNC クライアント（人が対話的に触る場合）

```
GDM でログイン → Hyprland セッション → virtio-gpu (DRM: Virtual-1)
         → QEMU が VNC でフレームバッファーを提供 (0.0.0.0:5910, コンテナー内)
         → Dev Container のポート転送
         → 手元の VNC クライアント
```

```sh
virsh -c qemu:///system list
virsh -c qemu:///system vncdisplay <domain>
```

ゲスト内に `wayvnc` を入れて `vagrant ssh -- -L 5900:127.0.0.1:5900` で SSH トンネル
越しに見る方法もあるが、Hyprland の headless 出力を別途作る必要があり手数が多いので
採らない。

## 9. Dev Container への変更

必要になる見込みのもの。実際に `vagrant up` を回して、必要だと確認できたものだけ入れる。

1. **`devcontainer.json` にポート転送を追加**（人が VNC で触る場合のみ）
   `"forwardPorts": [5910]` を追加する。DevPod でも効かせるなら `appPort` を使う。
   どちらもコンテナーの再作成が要る。第 10 章の自動確認はコンテナー内で完結するため、
   これが無くても検証そのものは回る。
2. **`allow_hosts.d` に Ghostty のビルドに要るホストを追加**（必須）
   `91-vagrant-guest` に次の 2 つを足す。どちらも現在の allowlist に無く、無いままだと
   070 の provisioning が `connection refused` で止まる。
   - `release.files.ghostty.org` … Ghostty のソース tarball
   - `ziglang.org` … mise の `core:zig` が取る Zig コンパイラー
3. **`Dockerfile` に `netpbm` を追加**（`virsh screenshot` が PPM を返した場合のみ）
   PPM のままでは画像として読めないので `pnmtopng` で PNG にする。libvirt 11.3 +
   QEMU 10.0 なら PNG が直接返る見込みなので、実際に 1 枚撮ってから要否を決める。
4. 上記以外は不要と考えている。VNC はコンテナー内の libvirt が listen し、
   `00-firewall` は INPUT を制限していないので、受信側の追加ルールは要らない。

コミットは `feat(devcontainer): ...` として Vagrantfile 側とは分けて積む。

## 10. 検証手順

### 手順 1: 起動と SSH

```sh
cd /workspaces/misc/vagrantfiles/hyprland-skk
vagrant up                      # 完走すること
vagrant ssh -c 'true'           # ログインできること
```

失敗したら原因を直してコミットし、`vagrant destroy -f && vagrant up` で
最初からやり直す。これを通るまで繰返す。

切り分けの最中は `vagrant provision` で当該のスクリプトだけ回してもよい。
そのぶん再現性が怪しくなるので、最後に手順 3 で作り直して確かめる。

### 手順 2: 画面とキーボードの確認

`vagrant up` が終わった時点で 140 が `graphical.target` まで入れているので、そのまま
各段階でキーを送っては `bin/screenshot` で 1 枚撮り、PNG を見て判定する。

130 が有効なら自動ログインが済んでいるので、1 の時点で既に Hyprland のセッションに
なっている。130 を外している場合だけ、2 の入力でログインする（パスワードは `vagrant`）。

| # | 送るキー | 期待する画面 |
| --- | --- | --- |
| 1 | （なし） | Hyprland のセッションが起動し、waybar が出ている |
| 2 | 130 を外している場合のみ: `KEY_V` `KEY_A` `KEY_G` `KEY_R` `KEY_A` `KEY_N` `KEY_T` を 1 回ずつ、最後に `KEY_ENTER` | GDM のログイン画面から Hyprland のセッションに入る |
| 3 | `KEY_RIGHTALT KEY_Q` | Ghostty のウィンドウが開く |
| 4 | `KEY_LEFTCTRL KEY_SPACE` → `KEY_A` `KEY_I` `KEY_U` | Ghostty に「あいう」が出る（Fcitx5-SKK） |
| 5 | `KEY_RIGHTALT KEY_R` | wofi が開き、Emacs Client / Ghostty / Chromium / テキストエディターの 4 項目が並ぶ |
| 6 | `KEY_C` `KEY_H` → `KEY_ENTER` | Chromium が起動する |
| 7 | アドレスバーで 4 と同じ手順 | 「あいう」が入る |
| 8 | wofi からテキストエディターを起動し 4 と同じ手順 | 「あいう」が入る |
| 9 | wofi から Emacs Client を起動し `KEY_LEFTCTRL KEY_X` → `KEY_LEFTCTRL KEY_J` → `KEY_A` `KEY_I` `KEY_U` | Emacs に「あいう」が出る（DDSKK） |

4・7・8 が Fcitx5-SKK の確認、9 が DDSKK の確認にあたる。SKK なので `aiu` の
ローマ字がそのまま「あいう」になり、変換操作までは踏み込まなくても判定できる。

補助的な確認コマンド（`vagrant ssh` から）:

```sh
systemctl status gdm           # ディスプレイマネージャー
loginctl list-sessions         # seat0 のセッションがあるか
hyprctl monitors               # Virtual-1 と解像度
hyprctl clients                # 起動中のウィンドウ
fcitx5-diagnose                # IM の状態一式
journalctl --user -u emacs     # Emacs デーモン
```

### 手順 3: 作り直しての再現確認

手順 1 と 2 が一通り通ったら、**VM を捨ててゼロから作り直し、同じ確認をやり直す**。

```sh
vagrant destroy -f
vagrant up
# 手順 1 の SSH 確認と、手順 2 の表をもういちど最初から通す
```

期待と違う結果が出たら、原因を直してコミットし、また `vagrant destroy -f` から
やり直す。**これを、何も直さずに通る回が出るまで繰返す。** 手順 3 が一度も修正を
挟まずに通った時点で完了とする。

この手順を分けて置く理由は、手順 1・2 の途中では `vagrant provision` や
`vagrant ssh` からの手作業で状態を直してしまいがちで、それが `provision_scripts` に
反映されていなくても手順 2 は通ってしまうため。作り直した回が通ることだけが、
スクリプトだけで環境が再現できる証拠になる。順序依存（あるスクリプトが前のスクリプトの
副作用に頼っている）も、ここで初めて露見することが多い。

box は `~/.vagrant.d`（名前付きボリューム）に残るので `vagrant destroy` しても
再ダウンロードは起きない。一方 Ghostty のソースビルドは毎回やり直しになるので、
1 周の所要時間はそこが支配的になる。

通った回のスクリーンショットは、確認できた証拠としてそのまま残しておく。

## 11. コミット計画

1. `feat(hyprland-skk): add a Vagrantfile that boots Debian GNU/Linux 13 on libvirt`
2. `feat(hyprland-skk): install Hyprland from trixie-backports`
3. `feat(hyprland-skk): install Emacs with DDSKK`
4. `feat(hyprland-skk): install Fcitx5 SKK for Wayland applications`
5. `feat(hyprland-skk): build Ghostty with mise and the asdf-ghostty plugin`
6. `feat(hyprland-skk): install Chromium and GNOME Text Editor`
7. `feat(hyprland-skk): install waybar and wofi`
8. `feat(hyprland-skk): log in to Hyprland through GDM`
9. `feat(hyprland-skk): let GDM log in automatically`
10. `feat(hyprland-skk): add a screenshot helper for checking the desktop`
11. `feat(devcontainer): ...`（必要が確認できた場合のみ）

途中で見つかった修正は、対応するコミットに `fix(hyprland-skk): ...` として積む。

## 12. リスクと代替案

| リスク | 影響 | 代替案 |
| --- | --- | --- |
| llvmpipe の描画が重い | Chromium のスクロールなどが遅い | 解像度を 1280x800 に落とす。アニメーション・blur は既に無効 |
| Ghostty のソースビルドが Zig のバージョン差で失敗する | 070 で provisioning が止まる | Ghostty 1.2.3 + Zig 0.14.1 の組（プラグインが対応表を持つ）に落とす |
| Ghostty のビルドに時間がかかる | `vagrant up` が長い、手順 3 の 1 周が長い | `VAGRANT_CPUS` を増やす。切り分け中は 070 だけ外して回し、手順 3 では必ず戻す |
| `release.files.ghostty.org` / `ziglang.org` が allowlist 外 | 070 で provisioning が止まる | 第 9 章の 2 を実施 |
| GTK の text-input-v3 で preedit が見にくい | 入力はできるが体験が悪い | `fcitx5-frontend-gtk4` + `GTK_IM_MODULE=fcitx` に切り替え（Ghostty は別途対処） |
| GDM が GNOME セッションでログインしてしまう | Hyprland が起動しない | 120 で AccountsService のファイルを書いたあと accounts-daemon を再起動する（対応済み） |
| GDM のグリーター（gnome-shell）が llvmpipe で重い | ログイン画面の描画が遅い | 130 の自動ログインで大半は素通りできる。グリーターを出す場合は解像度を下げる |
| `/etc/gdm3/daemon.conf` の書式が版で変わる | 130 が効かず、ログイン画面で止まる | `vagrant ssh` から `grep -A3 '\[daemon\]' /etc/gdm3/daemon.conf` で確認する。効かなくても第 10 章の 2 でログインできるので検証は続けられる |
| `emacs` の user unit が Debian に無い | Emacs Client がメニューから起動しない | `~/.config/systemd/user/emacs.service` を自作する |
| `virsh screenshot` が PPM を返す | 撮った画像をそのまま読めない | 第 9 章の 3（`netpbm` の追加）を実施 |
| 画面が消灯していて真っ黒が撮れる | 判定できない | 撮る前に無害なキーを送って起こす |
| ポインター操作が要る場面が出る | その項目だけ自動確認できない | キーボードだけで到達できる手順に組み替える。それも駄目なら人が VNC で触る |
