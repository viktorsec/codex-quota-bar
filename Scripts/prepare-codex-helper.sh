#!/bin/bash
# Download at development time only. The installed app never downloads executables.
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
version="0.164.0"
arch="${1:-$(uname -m)}"
case "$arch" in
    arm64)
        triple="aarch64-apple-darwin"
        checksum="2eb75238651acb7d5c7cbb088b56433c71bbb680189c3bbd50318589858d57b1"
        ;;
    x86_64)
        triple="x86_64-apple-darwin"
        checksum="8bcb46d2eb100ddccd81446339496e35c4f9640639339691d19dda551bb67a3f"
        ;;
    *) echo "Unsupported architecture: $arch" >&2; exit 1 ;;
esac
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
archive="codex-app-server-$triple.tar.gz"
curl --fail --location --proto '=https' --tlsv1.2 \
    "https://github.com/openai/codex/releases/download/rust-v$version/$archive" \
    --output "$work_dir/$archive"
echo "$checksum  $work_dir/$archive" | shasum -a 256 --check
tar -xzf "$work_dir/$archive" -C "$work_dir"
mkdir -p "$repo_dir/Vendor/Codex/$arch"
install -m 755 "$work_dir/codex-app-server-$triple" "$repo_dir/Vendor/Codex/$arch/codex-app-server"
echo "Prepared Codex app-server $version ($arch)."
