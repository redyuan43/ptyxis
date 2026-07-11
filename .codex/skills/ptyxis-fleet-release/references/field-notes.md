# Field Notes

## Verified Fleet

x86_64:

- `ivan`
- `ai`
- `MI`

aarch64:

- `edge`
- `spark`
- `agx`
- `nx1`, `nx2`, `nx3`, `nx4`
- `nano1`, `nano2`, `nano3`

## x86 Build Host

The AI host is the preferred x86 builder because it has many CPU cores. The
repository path is normally:

```text
/home/ai/github/ptyxis
```

The user Flatpak GNOME Platform and SDK 50 must be installed. The build uses a
release manifest generated from `org.gnome.Ptyxis.Devel.json` with:

- app ID `org.gnome.Ptyxis`
- runtime version `50`
- `development=false`
- local repository source
- `/app/lib64/pkgconfig:/app/lib/pkgconfig`
- Meson tests as the module post-install command

Older `flatpak-builder` versions can compile and install all 122 targets, then
fail at:

```text
bwrap: execvp appstream-compose: No such file or directory
```

Accept this only when the log proves compilation, installation, and tests
succeeded and the failure is exactly the AppStream compose step. Finalize and
export the build directory manually with `flatpak build-finish`,
`flatpak build-export`, and `flatpak build-bundle`.

## ARM GitHub Build

The workflow `.github/workflows/arm64-release.yml` uses:

```text
runs-on: ubuntu-24.04-arm
```

Ubuntu's packaged `flatpak-builder` did not support `--run-tests`. Tests are
therefore attached to the Ptyxis module's `post-install` commands:

```text
meson test --print-errorlogs
```

`post-install` already runs from `_flatpak_build`; do not add
`-C _flatpak_build`, which creates a duplicated path and fails after a complete
122/122 compilation.

## Flatpak Loader Compatibility

The bundle installs VTE and related libraries under `/app/lib64`. Some hosts
need:

```bash
flatpak override --user \
  --env=LD_LIBRARY_PATH=/app/lib64 \
  org.gnome.Ptyxis
```

Without the override, the symptom is:

```text
error while loading shared libraries: libvte-2.91-gtk4.so.0
```

## VPN for Flathub

The Ptyxis ARM bundle is small, but first installation also downloads GNOME
Platform 50, GL, codecs, locale, and sometimes NVIDIA driver extensions. This
can be hundreds of megabytes per device.

When direct Flathub access is slow, open a temporary reverse tunnel from the
controller:

```bash
ssh -fN \
  -o ExitOnForwardFailure=yes \
  -R 127.0.0.1:17891:127.0.0.1:10808 \
  edge
```

Then install remotely with:

```bash
export http_proxy=http://127.0.0.1:17891
export https_proxy=http://127.0.0.1:17891
export HTTP_PROXY="$http_proxy"
export HTTPS_PROXY="$https_proxy"
flatpak install --user --noninteractive -y BUNDLE
```

Flatpak keeps downloaded OSTree objects. Restarting an interrupted install
reuses the cache.

Avoid launching ten first-time runtime downloads without a proxy. If broad
parallelism saturates the controller, reduce fleet jobs to two or three.

## GUI Verification

`--version` verifies executable loading but not GTK window creation.

Direct GUI startup over SSH fails when the remote user has no accessible
Wayland/X11 session:

```text
Gtk-WARNING: Failed to open display
```

Use `xvfb-run` for headless initialization:

```bash
timeout 15 dbus-run-session -- \
  xvfb-run -a \
  flatpak run org.gnome.Ptyxis -s -- sh -lc "sleep 2"
```

An exit code of `0` is a clean test. Exit `124` is also evidence that the GUI
started when the log contains no display, loader, assertion, or crash error;
the standalone process simply remained alive until the timeout.

Some hosts can have stale Xauthority state. Retry with the host's existing
Xvfb display and matching `XAUTHORITY`, or test in a real logged-in desktop
session.

Flatpak can also fail before startup when a long-running document portal has
lost its FUSE mount:

```text
bwrap: Can't find source path /run/user/1000/doc/by-app/org.gnome.Ptyxis
```

Restart `xdg-document-portal.service` in the user's systemd session and retry.

## GitHub CLI Compatibility

Some fleet controllers have a `gh release download` implementation without
the `--clobber` option. Remove an incomplete cached bundle/checksum pair before
downloading instead of relying on that flag.
