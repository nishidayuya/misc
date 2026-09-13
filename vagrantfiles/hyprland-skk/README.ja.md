# hyprland-skk

[English](README.en.md) | 日本語

Debian GNU/Linux 13 (trixie) の上に Hyprland のデスクトップを作り、SKK で日本語入力が
できる状態までを Vagrant で再現する。Emacs は DDSKK、Ghostty / Chromium / GNOME
テキストエディターは Fcitx5-SKK で入力する。すべて Wayland ネイティブで動かしており、
`GDK_BACKEND=x11` も `--ozone-platform=x11` も使っていない。

設計は [docs/010-design.md](docs/010-design.md) を参照。

## 必要なもの

ホスト側に次のものが要る。

| | 用途 |
| --- | --- |
| Linux (x86_64 / arm64) | KVM が要るため。macOS / Windows では動かない |
| `/dev/kvm` | 無いと QEMU が CPU をエミュレートし、`vagrant up` が数時間かかる |
| Docker | DevPod の docker プロバイダーが使う |
| [DevPod CLI](https://devpod.sh/docs/getting-started/install) | Dev Container を起動する |
| VNC クライアント | 画面を見る。TigerVNC、Remmina、`virt-viewer` など |
| メモリー 8GB 以上 | VM が 4GB 使う |
| ディスク 20GB 以上 | box、VM ディスク、コンテナーイメージの合計 |

Vagrant、libvirt、QEMU はコンテナーの中に入っているので、ホストには要らない。

## 起動

### 1. Dev Container を起動する

`DOT_DEVCONTAINER_HOME` はコンテナーのホームに symlink するファイルを置くディレクトリー
で、上流の [dot-devcontainer](https://github.com/nishidayuya/dot-devcontainer) が必須に
している。空のディレクトリーでよい。

開くのはリポジトリールートではなく `vagrantfiles` ディレクトリー。

```sh
export DOT_DEVCONTAINER_HOME="$HOME/dev_container_home"
mkdir -p "$DOT_DEVCONTAINER_HOME"

cd /path/to/misc
devpod up ./vagrantfiles --ide none
```

初回はイメージのビルドで 10 分ほどかかる。ワークスペース名は `devpod list` で確認できる
（以降 `<workspace>` と書く）。

### 2. VM を起動する

```sh
devpod ssh <workspace>
cd hyprland-skk
vagrant up
```

`vagrant up` は 20〜30 分かかる。大半は Ghostty のソースビルド（`zig build`）で、
`VAGRANT_CPUS` を増やすと短くなる。

完了した時点で GDM の自動ログインが済み、Hyprland のセッションが動いている。
`vagrant reload` は要らない。

## 画面を見る

`devpod ssh` のポートフォワードで VM の VNC コンソールをホストに出す。**ホスト側の
別の端末**で実行する。

```sh
devpod ssh -L 5910:localhost:5910 <workspace>
```

このセッションを開いたまま、さらに別の端末から VNC クライアントで繋ぐ。

```sh
vncviewer localhost:5910
```

- ポート 5910 は VNC のディスプレイ番号 `:10` にあたる。クライアントによっては
  `localhost:10` や `localhost::5910` という書き方を要求する。
- フォワードを張りっぱなしにしたくなければ `--forward-ports-timeout 1h` を付けると、
  使われなくなった時点で終了する。
- ポートは `VAGRANT_GRAPHICS_PORT` で変えられる。

### 画面の中での操作

| キー | 動作 |
| --- | --- |
| `Super+Q` | Ghostty を起動 |
| `Super+R` | wofi のアプリケーションメニュー |
| `Super+C` | ウィンドウを閉じる |
| `Super+M` | Hyprland を終了 |
| `Ctrl+Space` | Fcitx5 の入力メソッド切り替え（US キーボード ↔ SKK） |
| `C-x C-j` | Emacs の中で DDSKK を有効にする |

wofi からは Emacs Client / Ghostty / Chromium / テキストエディターが起動できる。
GDM のログインが必要になった場合の資格情報は `vagrant` / `vagrant`。

## 停止と削除

VM とコンテナーは別々に落とす。**VM を先に片付ける**こと。コンテナーを先に消すと、
VM のディスクイメージが名前付きボリュームに取り残される。

```sh
# VM を止める（ディスクは残る。次の vagrant up は速い）
vagrant halt

# VM を消す
vagrant destroy -f
```

```sh
# コンテナーを止める（イメージとボリュームは残る）
devpod stop <workspace>

# コンテナーを消す
devpod delete <workspace>
```

box と VM ディスクは `devpod delete` では消えない。docker の名前付きボリュームに
置いてあり、コンテナーを作り直しても生き残るようにしてあるため。完全に消すなら次を
実行する。

```sh
docker volume rm vagrantfiles-vagrant-home vagrantfiles-libvirt-images
```

## 環境変数

`vagrant up` の前に設定する。

| 変数 | 既定値 | 用途 |
| --- | --- | --- |
| `VAGRANT_CPUS` | ホストの半分（最低 2） | vCPU 数 |
| `VAGRANT_MEMORY` | `4096` | メモリー (MB) |
| `VAGRANT_GRAPHICS_PORT` | `5910` | VNC の待ち受けポート |
| `GHOSTTY_VERSION` | `1.3.1` | ビルドする Ghostty の版 |
| `ZIG_VERSION` | `0.15.2` | それをビルドする Zig の版。Ghostty の版と対応している |

## 補足

- **描画は llvmpipe（CPU）**。virtio-gpu に 3D アクセラレーションを入れていないため、
  解像度を上げるほど重くなる。既定の 1920x1080 は `~/.config/hypr/hyprland.conf` の
  `monitor =` 行で変えられる（provisioning で上書きされるので、恒久的に変えるなら
  `provision_scripts/110-configure_hyprland` を編集する）。
- **VM の中を CLI で見る**には `vagrant ssh`。Hyprland の状態は
  `XDG_RUNTIME_DIR=/run/user/1000 hyprctl -i 0 monitors` のように見る。
