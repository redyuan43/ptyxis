#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: install-flatpak-host.sh BUNDLE VERSION [PROXY_URL]"
}

if [[ ${1:-} == -h || ${1:-} == --help ]]; then
  usage
  exit 0
fi

bundle=${1:-}
version=${2:-}
proxy_url=${3:-}
[[ -n "$bundle" && -n "$version" ]] || { usage >&2; exit 2; }
[[ -f "$bundle" ]] || { echo "Missing bundle: $bundle" >&2; exit 1; }

if ! command -v flatpak >/dev/null; then
  sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y flatpak
fi

flatpak remote-add --user --if-not-exists flathub \
  https://flathub.org/repo/flathub.flatpakrepo

if [[ -n "$proxy_url" ]]; then
  export http_proxy=$proxy_url
  export https_proxy=$proxy_url
  export HTTP_PROXY=$proxy_url
  export HTTPS_PROXY=$proxy_url
fi

ptyxis_version() {
  local output
  local rc

  set +e
  output=$(flatpak run --command=ptyxis org.gnome.Ptyxis --version 2>&1)
  rc=$?
  set -e

  if ((rc != 0)) && grep -q '/run/user/.*/doc/by-app/' <<<"$output"; then
    systemctl --user restart xdg-document-portal.service
    sleep 2
    output=$(flatpak run --command=ptyxis org.gnome.Ptyxis --version 2>&1)
  elif ((rc != 0)); then
    printf '%s\n' "$output" >&2
    return "$rc"
  fi

  sed -n '1s/^Ptyxis //p' <<<"$output"
}

installed_version=
if flatpak info org.gnome.Ptyxis >/dev/null 2>&1; then
  installed_version=$(ptyxis_version)
fi

if [[ "$installed_version" == "$version" ]]; then
  echo "INSTALL_SKIPPED already at Ptyxis $version"
elif [[ -n "$installed_version" ]]; then
  flatpak install --user --reinstall --noninteractive -y "$bundle"
else
  flatpak install --user --noninteractive -y "$bundle"
fi

flatpak override --user \
  --env=LD_LIBRARY_PATH=/app/lib64 \
  org.gnome.Ptyxis

reported=$(ptyxis_version)
[[ "$reported" == "$version" ]] || {
  echo "Expected Ptyxis $version, found $reported" >&2
  exit 1
}

echo "VERSION_OK Ptyxis $reported"

if ! command -v xvfb-run >/dev/null; then
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y xvfb
fi

gui_log=/tmp/ptyxis-gui-verification.log
set +e
timeout 15 dbus-run-session -- xvfb-run -a \
  flatpak run org.gnome.Ptyxis -s -- sh -lc "sleep 2" \
  >"$gui_log" 2>&1
gui_rc=$?
set -e

if ((gui_rc != 0)) && grep -q 'Failed to open display' "$gui_log"; then
  xvfb_command=$(ps -eo args= | grep -m1 '[X]vfb :[0-9]' || true)
  if [[ $xvfb_command =~ Xvfb[[:space:]]+(:[0-9]+) ]]; then
    existing_display=${BASH_REMATCH[1]}
    existing_xauthority=
    if [[ $xvfb_command =~ -auth[[:space:]]+([^[:space:]]+) ]]; then
      existing_xauthority=${BASH_REMATCH[1]}
    fi

    set +e
    DISPLAY=$existing_display XAUTHORITY=$existing_xauthority \
      timeout 15 dbus-run-session -- \
      flatpak run org.gnome.Ptyxis -s -- sh -lc "sleep 2" \
      >"$gui_log" 2>&1
    gui_rc=$?
    set -e
  fi
fi

if ((gui_rc == 0)); then
  echo "GUI_OK clean-exit"
elif ((gui_rc == 124)) &&
     ! grep -Eq 'Failed to open display|error while loading|Segmentation|assertion.*failed' "$gui_log"; then
  echo "GUI_OK remained-running-until-timeout"
else
  echo "GUI_UNVERIFIED rc=$gui_rc log=$gui_log" >&2
  grep -E 'Failed to open display|error while loading|Segmentation|assertion.*failed' \
    "$gui_log" >&2 || true
  exit 1
fi
