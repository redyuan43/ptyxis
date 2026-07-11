#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: build-x86-flatpak.sh --version VERSION [--output-dir DIR]

Builds and tests a release Flatpak from the current Ptyxis checkout.
EOF
}

version=
output_dir=dist

while (($#)); do
  case "$1" in
    --version)
      version=${2:?missing version}
      shift 2
      ;;
    --output-dir)
      output_dir=${2:?missing output directory}
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

[[ -n "$version" ]] || { usage >&2; exit 2; }
[[ $(uname -m) == x86_64 ]] || {
  echo "This builder requires x86_64; found $(uname -m)" >&2
  exit 1
}

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

project_version=$(sed -n "s/.*version: '\\([^']*\\)'.*/\\1/p" meson.build | head -1)
[[ "$project_version" == "$version" ]] || {
  echo "meson.build version is $project_version, expected $version" >&2
  exit 1
}

for command in flatpak flatpak-builder jq ostree sha256sum; do
  command -v "$command" >/dev/null || {
    echo "Missing required command: $command" >&2
    exit 1
  }
done

flatpak info --user org.gnome.Sdk//50 >/dev/null
flatpak info --user org.gnome.Platform//50 >/dev/null

work_root=${PTYXIS_BUILD_ROOT:-"$repo_root/.flatpak-release"}
build_dir="$work_root/build"
repo_dir="$work_root/repo"
manifest="$work_root/org.gnome.Ptyxis.Release.json"
log="$work_root/flatpak-builder.log"
bundle="$output_dir/ptyxis-$version-x86_64.flatpak"

rm -rf "$build_dir" "$repo_dir"
mkdir -p "$work_root" "$output_dir"

jq --arg source "$repo_root" '
  ."app-id" = "org.gnome.Ptyxis"
  | ."runtime-version" = "50"
  | ."build-options"."prepend-pkg-config-path" =
      "/app/lib64/pkgconfig:/app/lib/pkgconfig"
  | .modules[-1]."config-opts" =
      ["-Ddevelopment=false", "-Dlibc-compat=true"]
  | .modules[-1].sources = [{"type": "dir", "path": $source}]
  | .modules[-1]."post-install" =
      ((.modules[-1]."post-install" // []) +
       ["meson test --print-errorlogs"])
' org.gnome.Ptyxis.Devel.json > "$manifest"

set +e
flatpak-builder --user --force-clean --disable-rofiles-fuse \
  --keep-build-dirs "$build_dir" "$manifest" 2>&1 | tee "$log"
builder_rc=${PIPESTATUS[0]}
set -e

if ((builder_rc != 0)); then
  grep -q "appstream-compose failed" "$log" || exit "$builder_rc"
  grep -q "Fail:[[:space:]]*0" "$log" || {
    echo "Builder reached AppStream fallback without passing tests" >&2
    exit "$builder_rc"
  }
fi

flatpak build "$build_dir" env LD_LIBRARY_PATH=/app/lib64 \
  /app/bin/ptyxis --version | grep -F "Ptyxis $version"

if ! grep -q '^command=ptyxis$' "$build_dir/metadata"; then
  flatpak build-finish \
    --command=ptyxis \
    --allow=devel \
    --device=dri \
    --filesystem=home \
    --filesystem=host \
    --share=ipc \
    --share=network \
    --socket=fallback-x11 \
    --socket=wayland \
    --talk-name=org.freedesktop.Flatpak \
    "$build_dir"
fi

mkdir -p "$repo_dir"
flatpak build-export --disable-sandbox --no-update-summary \
  "$repo_dir" "$build_dir" master
ostree --repo="$repo_dir" summary -u
rm -f "$bundle" "$bundle.sha256"
flatpak build-bundle "$repo_dir" "$bundle" \
  org.gnome.Ptyxis master --arch=x86_64 \
  --runtime-repo=https://flathub.org/repo/flathub.flatpakrepo
(
  cd "$output_dir"
  sha256sum "$(basename "$bundle")" | tee "$(basename "$bundle").sha256"
)

echo "Built: $bundle"

