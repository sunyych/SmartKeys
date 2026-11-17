#!/usr/bin/env bash
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
[[ $# -eq 1 ]] || { echo "Usage: $0 /path/to/new-export-directory" >&2; exit 2; }
out="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1")"
case "$out/" in "$repo/"*) echo "Export destination must be outside the source repository: $out" >&2; exit 2;; esac
[[ ! -e "$out" ]] || { echo "Refusing to overwrite existing path: $out" >&2; exit 2; }
parent="$(dirname "$out")"
mkdir -p "$parent"
stage="$(mktemp -d "$parent/.smartkeys-export.XXXXXX")"
cleanup() { rm -rf "$stage"; }
trap cleanup EXIT
mkdir -p "$stage/lumia-key-full" "$stage/lumia-key-bluetooth-lite"
exclude_args=(
  --exclude='.git/' --exclude='**/build/' --exclude='**/dist/' --exclude='outputs/'
  --exclude='**/.dart_tool/' --exclude='.flutter-plugins-dependencies'
  --exclude='**/.idea/' --exclude='.scratch/' --exclude='**/.gradle/'
  --exclude='**/target/' --exclude='**/node_modules/' --exclude='**/.cache/'
  --exclude='**/.env' --exclude='**/.env.*' --exclude='**/*.jks' --exclude='**/*.keystore'
  --exclude='**/key.properties' --exclude='**/local.properties'
)
rsync -a "${exclude_args[@]}" --exclude='apps/bluetooth/' --exclude='scripts/build-bluetooth-lite.sh' --exclude='.github/workflows/bluetooth-lite.yml' "$repo/" "$stage/lumia-key-full/"
rsync -a "${exclude_args[@]}" "$repo/apps/bluetooth/" "$stage/lumia-key-bluetooth-lite/"
cat > "$stage/README.txt" <<'TXT'
Independent source exports for LumiaKey Full and LumiaKey Bluetooth Lite. Lite is a standalone Android Flutter project with its own build, dependency checks, tests, screenshots, and CI workflow. These folders contain no Git repositories or remotes.
TXT
mv "$stage" "$out"
trap - EXIT
printf 'Exported Full and Bluetooth Lite source folders to %s\n' "$out"
