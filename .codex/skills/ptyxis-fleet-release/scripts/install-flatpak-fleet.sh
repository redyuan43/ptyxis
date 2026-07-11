#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: install-flatpak-fleet.sh --tag TAG --hosts "HOST ..." [options]

Options:
  --repo OWNER/REPO       GitHub repository (default: redyuan43/ptyxis)
  --jobs N                Concurrent host installs (default: 3)
  --proxy-port PORT       Local HTTP proxy port (default: 10808)
  --remote-proxy-port P   Remote reverse-tunnel port (default: 17891)
  --no-proxy              Do not create SSH reverse proxy tunnels
EOF
}

tag=
hosts=
repo=redyuan43/ptyxis
jobs=3
proxy_port=10808
remote_proxy_port=17891
use_proxy=1

while (($#)); do
  case "$1" in
    --tag) tag=${2:?missing tag}; shift 2 ;;
    --hosts) hosts=${2:?missing hosts}; shift 2 ;;
    --repo) repo=${2:?missing repository}; shift 2 ;;
    --jobs) jobs=${2:?missing jobs}; shift 2 ;;
    --proxy-port) proxy_port=${2:?missing port}; shift 2 ;;
    --remote-proxy-port) remote_proxy_port=${2:?missing port}; shift 2 ;;
    --no-proxy) use_proxy=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -n "$tag" && -n "$hosts" ]] || { usage >&2; exit 2; }
[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || { echo "Invalid jobs: $jobs" >&2; exit 2; }

for command in gh ssh scp sha256sum ss; do
  command -v "$command" >/dev/null || {
    echo "Missing required command: $command" >&2
    exit 1
  }
done

if ((use_proxy)); then
  ss -ltn | grep -q "127.0.0.1:$proxy_port" || {
    echo "No local proxy listening on 127.0.0.1:$proxy_port" >&2
    exit 1
  }
fi

version=${tag#v}
cache_dir=${XDG_CACHE_HOME:-"$HOME/.cache"}/ptyxis-fleet-release/$tag
mkdir -p "$cache_dir"

download_asset() {
  local arch=$1
  local bundle="ptyxis-$version-$arch.flatpak"
  if [[ ! -f "$cache_dir/$bundle" || ! -f "$cache_dir/$bundle.sha256" ]]; then
    rm -f "$cache_dir/$bundle" "$cache_dir/$bundle.sha256"
    gh release download "$tag" --repo "$repo" \
      --pattern "$bundle*" --dir "$cache_dir"
  fi
  (cd "$cache_dir" && sha256sum -c "$bundle.sha256")
}

declare -A host_arch
for host in $hosts; do
  arch=$(ssh -o BatchMode=yes -o ConnectTimeout=12 "$host" uname -m)
  case "$arch" in
    x86_64) asset_arch=x86_64 ;;
    aarch64|arm64) asset_arch=aarch64 ;;
    *) echo "$host: unsupported architecture $arch" >&2; exit 1 ;;
  esac
  host_arch["$host"]=$asset_arch
done

declare -A downloaded_arch
for arch in "${host_arch[@]}"; do
  if [[ -z ${downloaded_arch[$arch]:-} ]]; then
    download_asset "$arch"
    downloaded_arch[$arch]=1
  fi
done

remote_installer=.codex/skills/ptyxis-fleet-release/scripts/install-flatpak-host.sh
repo_root=$(git rev-parse --show-toplevel)
remote_installer="$repo_root/$remote_installer"

install_host() {
  local host=$1
  local arch=${host_arch[$host]}
  local bundle="ptyxis-$version-$arch.flatpak"
  local proxy_url=

  echo "[$host] transferring $bundle"
  scp -q "$cache_dir/$bundle" "$host:/tmp/$bundle"
  scp -q "$remote_installer" "$host:/tmp/install-flatpak-host.sh"

  if ((use_proxy)); then
    printf -v proxy_probe \
      'curl -fsSI --max-time 8 --proxy %q https://flathub.org >/dev/null' \
      "http://127.0.0.1:$remote_proxy_port"
    # shellcheck disable=SC2029
    if ! ssh "$host" "$proxy_probe" 2>/dev/null; then
      ssh -fN \
        -o ExitOnForwardFailure=yes \
        -o ServerAliveInterval=30 \
        -R "127.0.0.1:$remote_proxy_port:127.0.0.1:$proxy_port" \
        "$host"
    fi
    proxy_url="http://127.0.0.1:$remote_proxy_port"
  fi

  printf -v remote_command \
    'chmod +x %q && %q %q %q %q' \
    /tmp/install-flatpak-host.sh \
    /tmp/install-flatpak-host.sh \
    "/tmp/$bundle" \
    "$version" \
    "$proxy_url"
  # shellcheck disable=SC2029
  ssh "$host" "$remote_command"
  echo "[$host] COMPLETE"
}

failures=0
batch_pids=()

wait_batch() {
  local pid

  for pid in "${batch_pids[@]}"; do
    if ! wait "$pid"; then
      ((failures += 1))
    fi
  done
  batch_pids=()
}

for host in $hosts; do
  install_host "$host" &
  batch_pids+=("$!")

  if ((${#batch_pids[@]} >= jobs)); then
    wait_batch
  fi
done

wait_batch

((failures == 0)) || {
  echo "$failures host installation(s) failed" >&2
  exit 1
}

echo "All requested hosts verified at Ptyxis $version"
