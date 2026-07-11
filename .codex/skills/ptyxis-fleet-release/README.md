# Ptyxis Fleet Release Skill

This skill automates the release path used by the `redyuan43/ptyxis` fork:

- build and test x86_64 Flatpak bundles on the AI build server
- build and test aarch64 bundles on GitHub's native ARM runner
- publish both architectures to one GitHub Release
- distribute the appropriate bundle to x86 and Jetson devices
- use the controller's VPN/xray proxy for slow Flathub runtime downloads
- apply Flatpak compatibility configuration and verify the application

## Commands

Build x86_64 on the current machine:

```bash
scripts/build-x86-flatpak.sh --version 50.3.1
```

Build x86_64 remotely on AI:

```bash
ssh ai 'cd ~/github/ptyxis && \
  .codex/skills/ptyxis-fleet-release/scripts/build-x86-flatpak.sh \
  --version 50.3.1'
```

Dispatch the GitHub ARM64 build:

```bash
scripts/dispatch-arm-release.sh --tag v50.3.1
```

Install the Jetson fleet:

```bash
scripts/install-flatpak-fleet.sh \
  --tag v50.3.1 \
  --hosts "edge spark agx nx1 nx2 nx3 nx4 nano1 nano2 nano3"
```

Install the x86 fleet:

```bash
scripts/install-flatpak-fleet.sh \
  --tag v50.3.1 \
  --hosts "ivan ai MI"
```

Disable the VPN tunnel only when direct Flathub access is known to work:

```bash
scripts/install-flatpak-fleet.sh \
  --tag v50.3.1 \
  --hosts "edge spark" \
  --no-proxy
```

## Prerequisites

Controller:

- `bash`, `git`, `gh`, `ssh`, `scp`, `sha256sum`
- authenticated `gh`
- passwordless SSH for target aliases
- optional HTTP proxy at `127.0.0.1:10808`

x86 build host:

- user Flatpak installation
- `org.gnome.Platform//50`
- `org.gnome.Sdk//50`
- `flatpak-builder`, `jq`, `ostree`, `appstream-compose`

Targets:

- Ubuntu with passwordless sudo, or Flatpak already installed
- enough storage for GNOME Platform 50

## Output Locations

The x86 builder writes:

```text
dist/ptyxis-VERSION-x86_64.flatpak
dist/ptyxis-VERSION-x86_64.flatpak.sha256
```

The fleet installer caches Release assets under:

```text
~/.cache/ptyxis-fleet-release/TAG/
```

## Troubleshooting

Read [references/field-notes.md](references/field-notes.md). It covers:

- old `flatpak-builder` AppStream failures after successful compilation
- `/app/lib64` loader overrides
- slow Flathub downloads and VPN reverse tunnels
- `already installed` bundle behavior
- headless GUI verification with Xvfb

