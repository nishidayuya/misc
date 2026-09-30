# vagrantfiles/.devcontainer

A Dev Container for running the Vagrant VMs in this directory, based on
[dot-devcontainer](https://github.com/nishidayuya/dot-devcontainer) **v4.3.1**.

`vagrant up` in a subdirectory boots a VM on QEMU/KVM inside this container,
and `vagrant ssh` logs into it.

## Usage

Open `vagrantfiles` (not the repository root) in VS Code and run
`Dev Containers: Reopen in Container`. `DOT_DEVCONTAINER_HOME` has to be set on
the host, as upstream requires. The mount starts one level up from the
workspace folder so that `.git` in the repository root is visible and git works
inside the container.

```sh
cd mise
vagrant up
vagrant ssh
```

## Which directories work in here

The provider is libvirt, so a directory works only if its box is published for
libvirt -- and only `mise` has actually been adapted so far.

| Directory | Box | State |
| --- | --- | --- |
| `mise` | `debian/bookworm64` 12.20250126.1 (libvirt and virtualbox) | works, and verified end to end |
| `redmine50-rhel8.10` | `alvistack/rhel-8` (libvirt only) | box is fine, but the Vagrantfile still needs the synced folder type and the `:libvirt` provider block that `mise/Vagrantfile` has |
| `redmine61`, `redmine60-centosstream10`, `redmine50-rockylinux8.10` | `bento/*` | **cannot work**: bento publishes virtualbox, parallels, vmware and utm, but no libvirt box |

Adapting another directory means copying the three things `mise/Vagrantfile`
does: read `VAGRANT_SYNCED_FOLDER_TYPE` into the `type:` of every
`synced_folder`, pick the read-only options by type (see below), and add a
`config.vm.provider(:libvirt)` block with the same cpus and memory as the
virtualbox one.

Note that Debian's own boxes have been moving to libvirt only:
`debian/trixie64` has never been published for virtualbox, and neither has any
`debian/bookworm64` release after 12.20250126.1.

## Local modifications to upstream

`install.sh` replaces `.devcontainer` wholesale (`rm -rf` then `mv`), so
everything below is lost when this directory is updated to a newer
dot-devcontainer and has to be reapplied. Files that upstream does not ship at
all survive nothing either; they are listed here too.

### `Dockerfile`

Two `RUN` instructions added before `USER vscode`:

1. `apt-get install` of `vagrant`, `vagrant-libvirt`, `libvirt-daemon-system`,
   `libvirt-clients`, the architecture's `qemu-system-*`, `qemu-utils`,
   `dnsmasq-base`, `nftables` and `rsync`. All of them come from Debian main.
2. Configuration of `/etc/libvirt/libvirtd.conf` and `/etc/libvirt/qemu.conf`
   for a container with neither systemd nor polkit, and `usermod -aG libvirt`
   for the vscode user. The reasoning is in the comments on that instruction.

### `devcontainer.json`

- `workspaceMount` / `workspaceFolder`: mount the repository root, open
  `vagrantfiles`.
- `mounts`: two named volumes, `vagrantfiles-vagrant-home` on
  `~/.vagrant.d` and `vagrantfiles-libvirt-images` on
  `/var/lib/libvirt/images`, so that boxes and VM disks survive a container
  rebuild.
- `containerEnv`: `VAGRANT_DEFAULT_PROVIDER=libvirt`,
  `VAGRANT_SYNCED_FOLDER_TYPE=9p`, `LIBVIRT_DEFAULT_URI=qemu:///system`.
- `runArgs`: `--device=/dev/kvm`.

### New files

- `allow_hosts.d/90-vagrant` — Vagrant Cloud and `api.cloud.hashicorp.com`,
  plus AWS CloudFront and S3 IP ranges, which together cover the redirect chain
  a box download walks.
- `allow_hosts.d/91-vagrant-guest` — `mise.run` and `cache.ruby-lang.org`,
  which the provisioning inside the VMs needs.
- `post_start_command.d/40-libvirt` — starts `virtlogd` and `libvirtd`, waits
  for them, and defines the `default` storage pool on the volume-backed path.
- `post_start_command.d/45-vagrant-vm-access` — opens the firewall to
  `192.168.121.0/24`, without which every connection to a VM is rejected.
- `post_start_command.d/46-vagrant-vm-egress` — holds the VMs to the same
  allowlist as the container.

## Firewall

The container's own outbound traffic is restricted by upstream's
`00-firewall`, which filters `OUTPUT`. A VM's traffic is routed rather than
generated here, so it traverses `FORWARD` and none of those rules apply to it.

`46-vagrant-vm-egress` closes that gap by re-expressing the addresses
`00-firewall` allowed as an nftables table of its own, on an earlier hook
priority than the filter table. It has to sit outside iptables: libvirt puts
`-A LIBVIRT_FWO -s 192.168.121.0/24 -i virbr1 -j ACCEPT` at the head of
`FORWARD` and re-establishes those jumps when a network starts, so an iptables
rule there is either never reached or displaced by the first `vagrant up`.

Note that the allowlist is address-based, so a host that shares a CDN with an
allowed one is reachable too. `www.ruby-lang.org` is an example: nothing lists
it, but upstream's `01-cdn-fastly` allows all of Fastly's ranges.

To let the VMs reach the internet unrestricted instead:

```sh
chmod -x .devcontainer/post_start_command.d/46-vagrant-vm-egress
```

`run-parts` skips a non-executable file, so it stays off from the next
container start. Reachability of the VMs is a separate script
(`45-vagrant-vm-access`) and keeps working either way.

When provisioning fails on a host that is not allowed yet, add it to
`allow_hosts.d/` and reapply the rules without restarting the container:

```sh
.devcontainer/post_start_command.d/00-firewall
.devcontainer/post_start_command.d/45-vagrant-vm-access
.devcontainer/post_start_command.d/46-vagrant-vm-egress
```

## Synced folders

`VAGRANT_SYNCED_FOLDER_TYPE` picks the synced folder type, and the Vagrantfiles
pass it through to `config.vm.synced_folder`. Unset, as it is on the host, the
type is left to the provider and VirtualBox uses vboxsf.

It is set to `9p` here rather than left to vagrant-libvirt, because 9p and
virtiofs are registered at the same priority as Vagrant's own nfs and rsync,
and an unspecified type resolves to whichever of them sorts first. If 9p turns
out to be a problem, `virtiofs` (add the `virtiofsd` package) and `rsync` are
the alternatives, and switching means changing that one variable.

One thing to watch for when adding `type: "9p"` to another Vagrantfile: 9p
ignores Vagrant's standard `mount_options`, so a folder declared with
`mount_options: %w[ro]` comes up **writable** in the guest. Its own keys are
`mount_opts` (a string, passed to the guest's `mount`) and `readonly` (which
marks the export read-only on the host side, the half a guest cannot undo).
`mise/Vagrantfile` picks between the two sets based on the type.

## Troubleshooting

`vagrant up` fails with an authentication error from libvirt
: The vscode user is not in the `libvirt` group. Check `id`, and that the
  `usermod` in the Dockerfile ran.

`vagrant up` is extremely slow
: KVM is not being used. Check that `/dev/kvm` exists in the container;
  `40-libvirt` refuses to start without it.

A download or `apt-get` inside the VM fails with "connection refused"
: The host is not on the allowlist. See the Firewall section above.
