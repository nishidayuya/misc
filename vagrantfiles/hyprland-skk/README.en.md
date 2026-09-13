# hyprland-skk

English | [日本語](README.ja.md)

Builds a Hyprland desktop on Debian GNU/Linux 13 (trixie) with Japanese input
through SKK, reproducibly, with Vagrant. Emacs uses DDSKK; Ghostty, Chromium and
GNOME Text Editor use Fcitx5 SKK. Everything runs natively on Wayland -- neither
`GDK_BACKEND=x11` nor `--ozone-platform=x11` is used.

The design is in [docs/010-design.md](docs/010-design.md) (Japanese).

## What you need

On the host:

| | Why |
| --- | --- |
| Linux (x86_64 / arm64) | KVM is required, so macOS and Windows will not do |
| `/dev/kvm` | Without it QEMU emulates the CPU and `vagrant up` takes hours |
| Docker | Used by DevPod's docker provider |
| [DevPod CLI](https://devpod.sh/docs/getting-started/install) | Brings the Dev Container up |
| A VNC client | To see the screen: TigerVNC, Remmina, `virt-viewer`, … |
| 8GB of memory or more | The VM takes 4GB |
| 20GB of disk or more | Box, VM disk and container image together |

Vagrant, libvirt and QEMU live inside the container, so the host does not need
them.

## Getting started

### 1. Start the Dev Container

`DOT_DEVCONTAINER_HOME` points at a directory whose files are symlinked into the
container's home; upstream
[dot-devcontainer](https://github.com/nishidayuya/dot-devcontainer) requires it.
An empty directory is fine.

Open the `vagrantfiles` directory, not the repository root.

```sh
export DOT_DEVCONTAINER_HOME="$HOME/dev_container_home"
mkdir -p "$DOT_DEVCONTAINER_HOME"

cd /path/to/misc
devpod up ./vagrantfiles --ide none
```

The first run spends about ten minutes building the image. `devpod list` prints
the workspace name, written `<workspace>` below.

### 2. Start the VM

```sh
devpod ssh <workspace>
cd hyprland-skk
vagrant up
```

`vagrant up` takes 20 to 30 minutes. Most of that is building Ghostty from
source with `zig build`, which `VAGRANT_CPUS` shortens.

When it finishes, GDM has already logged in automatically and the Hyprland
session is running. No `vagrant reload` is needed.

## Seeing the screen

Forward the VM's VNC console to the host with `devpod ssh`. Run this in
**another terminal on the host**:

```sh
devpod ssh -L 5910:localhost:5910 <workspace>
```

Leave that session open and connect a VNC client from a third terminal:

```sh
vncviewer localhost:5910
```

- Port 5910 is VNC display `:10`. Some clients want it written as
  `localhost:10` or `localhost::5910`.
- To avoid holding the forward open indefinitely, add
  `--forward-ports-timeout 1h` and it ends once the port goes unused.
- `VAGRANT_GRAPHICS_PORT` changes the port.

### Driving the desktop

| Key | What it does |
| --- | --- |
| `Super+Q` | Start Ghostty |
| `Super+R` | wofi's application menu |
| `Super+C` | Close the window |
| `Super+M` | Exit Hyprland |
| `Ctrl+Space` | Switch Fcitx5's input method (US keyboard ↔ SKK) |
| `C-x C-j` | Turn DDSKK on inside Emacs |

wofi starts Emacs Client, Ghostty, Chromium and Text Editor. Should GDM ever ask
for credentials, they are `vagrant` / `vagrant`.

## Shutting down and removing

The VM and the container come down separately. **Deal with the VM first**:
deleting the container first strands the VM's disk image in a named volume.

```sh
# Stop the VM, keeping its disk. The next "vagrant up" is quick
vagrant halt

# Delete the VM
vagrant destroy -f
```

```sh
# Stop the container, keeping the image and the volumes
devpod stop <workspace>

# Delete the container
devpod delete <workspace>
```

`devpod delete` does not remove the box or the VM disks. They sit in docker
named volumes, deliberately, so that they survive a container rebuild. To get
rid of them too:

```sh
docker volume rm vagrantfiles-vagrant-home vagrantfiles-libvirt-images
```

## Environment variables

Set these before `vagrant up`.

| Variable | Default | Meaning |
| --- | --- | --- |
| `VAGRANT_CPUS` | Half the host's, at least 2 | Number of vCPUs |
| `VAGRANT_MEMORY` | `4096` | Memory in MB |
| `VAGRANT_GRAPHICS_PORT` | `5910` | Port the VNC console listens on |
| `GHOSTTY_VERSION` | `1.3.1` | Ghostty release to build |
| `ZIG_VERSION` | `0.15.2` | Zig that builds it; the two versions go together |

## Notes

- **The VNC console has no authentication.** It listens on `0.0.0.0:5910`
  inside the container, so anything that can reach the container's address can
  drive the screen. On a shared host, set `libvirt.graphics_ip` in the
  `Vagrantfile` to `"127.0.0.1"` and reach it only through the port forward
  above.
- **To turn autologin off**, drop the execute bit so that `run-parts` skips the
  script. GDM itself stays, so a login screen appears instead.

  ```sh
  chmod -x provision_scripts/130-enable_gdm_autologin
  vagrant destroy -f && vagrant up
  ```

- **Everything is drawn by llvmpipe on the CPU.** There is no 3D acceleration on
  the virtio GPU, so a higher resolution costs more. The default 1920x1080 comes
  from the `monitor =` line in `~/.config/hypr/hyprland.conf`; change
  `provision_scripts/110-configure_hyprland` to make it stick, since
  provisioning rewrites that file.
- **To look inside the VM from a shell**, use `vagrant ssh`. Hyprland's state
  reads back with e.g.
  `XDG_RUNTIME_DIR=/run/user/1000 hyprctl -i 0 monitors`.
