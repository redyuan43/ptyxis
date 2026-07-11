#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: dispatch-arm-release.sh --tag TAG [--repo OWNER/REPO]"
}

tag=
repo=redyuan43/ptyxis

while (($#)); do
  case "$1" in
    --tag)
      tag=${2:?missing tag}
      shift 2
      ;;
    --repo)
      repo=${2:?missing repository}
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

[[ -n "$tag" ]] || { usage >&2; exit 2; }
command -v gh >/dev/null

gh release view "$tag" --repo "$repo" >/dev/null
gh workflow run arm64-release.yml --repo "$repo" -f "tag=$tag"

sleep 3
run_id=$(
  gh run list --repo "$repo" --workflow arm64-release.yml \
    --event workflow_dispatch --limit 1 \
    --json databaseId --jq '.[0].databaseId'
)

echo "Watching ARM64 run $run_id"
gh run watch "$run_id" --repo "$repo" --exit-status

version=${tag#v}
assets=$(gh release view "$tag" --repo "$repo" --json assets --jq '.assets[].name' 2>/dev/null || true)
grep -Fx "ptyxis-$version-aarch64.flatpak" <<<"$assets"
grep -Fx "ptyxis-$version-aarch64.flatpak.sha256" <<<"$assets"

echo "ARM64 assets published to $tag"
