---
name: ptyxis-fleet-release
description: Build, test, publish, install, configure, and verify this Ptyxis fork across the user's x86_64 and Jetson aarch64 fleet. Use this skill whenever the user asks to compile Ptyxis on AI, publish x86 or ARM Flatpak assets, run the GitHub ARM workflow, install a Ptyxis release on ivan/AI/MI or edge/spark/agx/nx/nano devices, use the VPN for slow Flathub downloads, or verify that every device can start the GUI.
compatibility: Requires bash, git, gh, jq, SSH access to the fleet, Flatpak tooling on build hosts, and an optional local HTTP proxy such as xray on 127.0.0.1:10808.
---

# Ptyxis Fleet Release

Use this skill as the operating runbook for this repository's release fork.
It captures the verified path from source commit to GitHub Release and fleet
installation.

## Start Here

1. Read [README.md](README.md) for commands and prerequisites.
2. Read [references/field-notes.md](references/field-notes.md) before changing
   build layout, proxy behavior, or GUI verification.
3. Keep the release tag immutable. Create a patch version instead of replacing
   assets for an older tag.
4. Verify each claim with command output before reporting completion.

## Release Workflow

For a new release:

1. Confirm `main` is clean except for known local state such as `.omx/`.
2. Update `meson.build` and AppStream release metadata.
3. Commit and push the source changes using the repository's Lore commit
   protocol.
4. Create and push an annotated release tag.
5. Build x86_64 on AI:

   ```bash
   .codex/skills/ptyxis-fleet-release/scripts/build-x86-flatpak.sh \
     --version 50.3.1
   ```

6. Create or update the GitHub Release with the x86_64 bundle and checksum.
7. Dispatch the native ARM64 GitHub build:

   ```bash
   .codex/skills/ptyxis-fleet-release/scripts/dispatch-arm-release.sh \
     --tag v50.3.1
   ```

8. Confirm both architectures and checksum files are present in the Release.

The ARM workflow lives at `.github/workflows/arm64-release.yml`. It must compile
and test on `ubuntu-24.04-arm`; do not substitute an unverified cross-build.

## Fleet Installation

Install a release from a controller with SSH access to the devices:

```bash
.codex/skills/ptyxis-fleet-release/scripts/install-flatpak-fleet.sh \
  --tag v50.3.1 \
  --hosts "edge spark agx nx1 nx2 nx3 nx4 nano1 nano2 nano3"
```

For the x86 fleet:

```bash
.codex/skills/ptyxis-fleet-release/scripts/install-flatpak-fleet.sh \
  --tag v50.3.1 \
  --hosts "ivan ai MI"
```

The script detects each host's architecture, downloads the matching GitHub
Release asset once, transfers it over SSH, installs missing Flatpak tooling,
applies the `/app/lib64` compatibility override, and verifies the version.

## Proxy Policy

Flathub and GitHub downloads on remote Jetson devices should use the controller
VPN when direct access is slow or unreliable. The fleet installer defaults to a
temporary SSH reverse tunnel:

```text
remote 127.0.0.1:17891 -> controller 127.0.0.1:10808
```

Downloaded OSTree objects are reusable. If a direct install is slow, stop it,
establish the tunnel, and rerun; do not delete Flatpak caches.

## Verification Standard

For every device, require:

- `uname -m` matches the selected Release asset.
- `flatpak info org.gnome.Ptyxis` succeeds.
- `flatpak run --command=ptyxis org.gnome.Ptyxis --version` reports the target
  version.
- `LD_LIBRARY_PATH=/app/lib64` is present as an app-specific Flatpak override
  on hosts whose loader does not discover bundled `lib64`.
- GUI initialization is tested in a real desktop session when available, or
  through Xvfb on headless devices.

Treat `Failed to open display` as a missing accessible graphical session, not
as proof that the Ptyxis binary is broken. Use the Xvfb verifier in the remote
installer to distinguish those cases.

## Expected Report

Report:

- source commit and tag
- x86_64 and aarch64 checksums
- GitHub Actions run ID and conclusion
- test counts
- per-host version verification
- any device that only received binary verification rather than GUI
  initialization

