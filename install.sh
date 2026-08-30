#!/bin/sh

set -eu

repo="Vozenio/Vozen"
version="v0.1.1"
force=0

usage() {
  cat <<'EOF'
Usage: install.sh [--version vX.Y.Z] [--force]

Installs the macOS Apple Silicon Vozen technical preview into:
  ~/.local/share/vozen/<version>

Creates ~/.local/bin/vozen. The installer never uses sudo.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version)
      [ "$#" -ge 2 ] || { echo "--version requires a value" >&2; exit 2; }
      version="$2"
      shift 2
      ;;
    --force)
      force=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

[ "$(uname -s)" = "Darwin" ] || { echo "Vozen preview currently supports macOS only." >&2; exit 1; }
[ "$(uname -m)" = "arm64" ] || { echo "Vozen preview currently supports Apple Silicon only." >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "curl is required." >&2; exit 1; }
command -v shasum >/dev/null 2>&1 || { echo "shasum is required." >&2; exit 1; }
command -v tar >/dev/null 2>&1 || { echo "tar is required." >&2; exit 1; }

archive="vozen-${version}-macos-arm64.tar.gz"
base_url="https://github.com/${repo}/releases/download/${version}"
share_root="${HOME}/.local/share/vozen"
bin_root="${HOME}/.local/bin"
install_dir="${share_root}/${version}"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/vozen-install.XXXXXX")"

cleanup() {
  rm -rf "$work_dir"
}
trap cleanup EXIT INT TERM

if [ -e "$install_dir" ] && [ "$force" -ne 1 ]; then
  echo "$install_dir already exists. Use --force to replace this version." >&2
  exit 1
fi

echo "Downloading Vozen ${version}..."
curl --fail --location --silent --show-error --output "$work_dir/$archive" "$base_url/$archive"
curl --fail --location --silent --show-error --output "$work_dir/$archive.sha256" "$base_url/$archive.sha256"

expected="$(awk 'NR == 1 { print $1 }' "$work_dir/$archive.sha256")"
actual="$(shasum -a 256 "$work_dir/$archive" | awk '{ print $1 }')"
[ -n "$expected" ] && [ "$expected" = "$actual" ] || {
  echo "SHA-256 verification failed; nothing was installed." >&2
  exit 1
}

tar -xzf "$work_dir/$archive" -C "$work_dir"
package_dir="$work_dir/vozen-${version}-macos-arm64"
[ -x "$package_dir/bin/vozen-server" ] || {
  echo "Archive is missing vozen-server; nothing was installed." >&2
  exit 1
}
[ -x "$package_dir/bin/vozen-daemon" ] || {
  echo "Archive is missing vozen-daemon; nothing was installed." >&2
  exit 1
}
mkdir -p "$share_root" "$bin_root"
if [ -e "$install_dir" ]; then
  rm -rf "$install_dir"
fi
mv "$package_dir" "$install_dir"
cat > "$bin_root/vozen" <<EOF
#!/bin/sh
exec "$install_dir/bin/vozen-server" "\$@"
EOF
chmod +x "$bin_root/vozen"

echo "Installed Vozen ${version}."
echo "Run: $bin_root/vozen"
case ":$PATH:" in
  *":$bin_root:"*) ;;
  *) echo "Add $bin_root to PATH to run: vozen" ;;
esac
